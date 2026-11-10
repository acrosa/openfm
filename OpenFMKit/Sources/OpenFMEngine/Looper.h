// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0
//
// A four-layer loop recorder. Each layer has its own synthesis engine, so it
// keeps the sound it was recorded with while the live engine moves on to
// another one.
//
// Recording is one pass: press record, hear a one-bar count-in (or wait for
// the loop to come round if it is already playing), play for one loop length,
// and the layer starts looping by itself.
//
// Threading
//   prepare()                              non-realtime, before process
//   setTempo/setBars/.../record/clear      any thread, wait-free (atomics)
//   capture() / process()                  the render thread only
//   state()                                any thread

#ifndef OPENFM_LOOPER_H_
#define OPENFM_LOOPER_H_

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>

#include "Engine.h"

namespace openfm {

class Looper {
 public:
  static constexpr int kLayers = 4;
  static constexpr int kMaxEvents = 512;

  struct State {
    bool playing = false;
    bool countingIn = false;
    int recordingLayer = -1;
    int armedLayer = -1;
    double positionBeats = 0;
    double lengthBeats = 8;
    uint32_t contentMask = 0;
  };

  Looper() {
    for (auto &layer : layers_) layer.engine = std::make_unique<Engine>();
  }

  void prepare(double sampleRate) {
    sampleRate_ = sampleRate;
    for (auto &layer : layers_) layer.engine->prepare(sampleRate);
  }

  // ---- Control ----------------------------------------------------------

  void setTempo(float bpm) { bpm_.store(std::fmin(std::fmax(bpm, 40.0f), 240.0f), std::memory_order_relaxed); }
  void setBars(int bars) { bars_.store(bars < 1 ? 1 : (bars > 8 ? 8 : bars), std::memory_order_relaxed); }
  void setMetronome(bool on) { metronome_.store(on, std::memory_order_relaxed); }
  void setQuantize(bool on) { quantize_.store(on, std::memory_order_relaxed); }
  void setPlaying(bool on) { requestPlay_.store(on ? 1 : 0, std::memory_order_release); }

  /// Gives `layer` the sound in `patch` / `fx` and records one pass into it.
  void record(int layer, const uint8_t patch[Engine::kPatchSize], const float fx[Engine::kFxCount]) {
    if (layer < 0 || layer >= kLayers) return;
    layers_[layer].engine->loadPatch(patch);
    for (int i = 0; i < Engine::kFxCount; i++) layers_[layer].engine->setFx(i, fx[i]);
    requestRecord_.store(layer, std::memory_order_release);
  }

  void clear(int layer) {
    if (layer < 0 || layer >= kLayers) return;
    requestClear_.fetch_or(1u << layer, std::memory_order_release);
  }

  void setMuted(int layer, bool muted) {
    if (layer < 0 || layer >= kLayers) return;
    if (muted) muted_.fetch_or(1u << layer, std::memory_order_release);
    else muted_.fetch_and(~(1u << layer), std::memory_order_release);
  }

  State state() const {
    State s;
    const int phase = statePhase_.load(std::memory_order_relaxed);
    s.playing = phase == kRunning;
    s.countingIn = phase == kCountIn;
    s.recordingLayer = stateRecording_.load(std::memory_order_relaxed);
    s.armedLayer = stateArmed_.load(std::memory_order_relaxed);
    s.positionBeats = statePosition_.load(std::memory_order_relaxed);
    s.lengthBeats = bars_.load(std::memory_order_relaxed) * 4.0;
    s.contentMask = stateContent_.load(std::memory_order_relaxed);
    return s;
  }

  // ---- Render thread ----------------------------------------------------

  /// A note just played live. Kept if a layer is recording.
  void capture(uint8_t status, uint8_t data1, uint8_t data2) {
    if (phase_ != kRunning || recording_ < 0) return;
    Layer &layer = layers_[recording_];
    const double length = lengthBeats();
    const int note = data1 & 0x7f;
    const bool on = (status & 0xf0) == 0x90 && data2 > 0;
    const bool off = (status & 0xf0) == 0x80 || ((status & 0xf0) == 0x90 && data2 == 0);
    if (!on && !off) return;
    if (layer.count >= kMaxEvents - 130) return;  // keep room for closing note-offs

    double at = position_;
    if (on) {
      if (quantize_.load(std::memory_order_relaxed)) at = std::round(at / kGrid) * kGrid;
      shift_[note] = at - position_;
      if (at >= length) at -= length;  // snapped onto the downbeat of the next pass
      held_[note] = true;
      layer.events[layer.count++] = {at, 0x90, (uint8_t)note, data2, pass_};
    } else {
      if (!held_[note]) return;
      held_[note] = false;
      at = std::fmin(position_ + shift_[note], length - 0.001);
      layer.events[layer.count++] = {at, 0x80, (uint8_t)note, 0, pass_};
    }
  }

  /// Advances the loop and adds the layers (and the click) to `left`/`right`.
  void process(float *left, float *right, int frames) {
    handleRequests();
    if (phase_ == kStopped) {
      if (tailFrames_ > 0) {
        renderLayers(left, right, frames);
        tailFrames_ -= frames;
      }
      publish();
      return;
    }

    const double beatsPerFrame = bpm_.load(std::memory_order_relaxed) / 60.0 / sampleRate_;
    int done = 0;
    while (done < frames) {
      const double length = lengthBeats();
      if (phase_ == kCountIn && position_ >= -1e-9) {
        phase_ = kRunning;
        position_ = 0;
        beginPass();
      } else if (phase_ == kRunning && position_ >= length - 1e-9) {
        position_ -= length;
        if (position_ < 0) position_ = 0;
        beginPass();
      }

      // A click on every beat while it is useful.
      const long beat = (long)std::floor(position_ + 1e-9);
      if (beat != lastBeat_) {
        lastBeat_ = beat;
        const bool wanted = metronome_.load(std::memory_order_relaxed) || phase_ == kCountIn ||
                            recording_ >= 0 || armed_ >= 0;
        if (wanted) startClick(((beat % 4) + 4) % 4 == 0);
      }

      // Run to the next beat, at most one engine block at a time so notes land
      // within a millisecond or so of where they were played.
      const double toBeat = (double)(beat + 1) - position_;
      int chunk = (int)std::ceil(toBeat / beatsPerFrame);
      chunk = std::max(1, std::min({chunk, frames - done, (int)N}));
      const double span = chunk * beatsPerFrame;

      if (phase_ == kRunning) fire(position_, position_ + span);
      renderLayers(left + done, right + done, chunk);
      renderClick(left + done, right + done, chunk);

      position_ += span;
      done += chunk;
    }
    publish();
  }

 private:
  enum Phase { kStopped = 0, kCountIn = 1, kRunning = 2 };
  static constexpr double kGrid = 0.25;  // sixteenth notes

  struct Event {
    double beat;
    uint8_t status, data1, data2;
    uint32_t pass;  // the pass it was recorded in
  };

  struct Layer {
    std::unique_ptr<Engine> engine;
    Event events[kMaxEvents];
    int count = 0;
    bool hasContent = false;
  };

  double lengthBeats() const { return bars_.load(std::memory_order_relaxed) * 4.0; }

  void silence(Layer &layer) { layer.engine->handleMidi(0xb0, 123, 0); }

  void handleRequests() {
    const uint32_t clear = requestClear_.exchange(0, std::memory_order_acq_rel);
    for (int i = 0; i < kLayers; i++) {
      if (!(clear & (1u << i))) continue;
      layers_[i].count = 0;
      layers_[i].hasContent = false;
      silence(layers_[i]);
      if (recording_ == i) recording_ = -1;
      if (armed_ == i) armed_ = -1;
    }

    const uint32_t muted = muted_.load(std::memory_order_acquire);
    for (int i = 0; i < kLayers; i++) {
      if ((muted & (1u << i)) && !(seenMuted_ & (1u << i))) silence(layers_[i]);
    }
    seenMuted_ = muted;

    const int record = requestRecord_.exchange(-1, std::memory_order_acq_rel);
    if (record >= 0) {
      armed_ = record;
      if (phase_ == kStopped) {
        phase_ = kCountIn;
        position_ = -4;
        lastBeat_ = -100;
      }
    }

    const int play = requestPlay_.exchange(-1, std::memory_order_acq_rel);
    if (play == 1 && phase_ == kStopped) {
      phase_ = kRunning;
      position_ = 0;
      lastBeat_ = -100;
      beginPass();
    } else if (play == 0 && phase_ != kStopped) {
      if (recording_ >= 0) finishRecording();
      armed_ = -1;
      phase_ = kStopped;
      for (auto &layer : layers_) silence(layer);
      tailFrames_ = (long)(4 * sampleRate_);
    }
  }

  /// The loop has come round (or just started).
  void beginPass() {
    pass_++;
    if (recording_ >= 0) finishRecording();
    if (armed_ >= 0) {
      recording_ = armed_;
      armed_ = -1;
      Layer &layer = layers_[recording_];
      layer.count = 0;
      layer.hasContent = false;
      silence(layer);
      std::memset(held_, 0, sizeof(held_));
      std::memset(shift_, 0, sizeof(shift_));
    }
  }

  void finishRecording() {
    Layer &layer = layers_[recording_];
    const double end = lengthBeats() - 0.001;
    for (int note = 0; note < 128; note++) {
      if (held_[note] && layer.count < kMaxEvents) {
        layer.events[layer.count++] = {end, 0x80, (uint8_t)note, 0, pass_ - 1};
      }
      held_[note] = false;
    }
    layer.hasContent = layer.count > 0;
    recording_ = -1;
  }

  void fire(double from, double to) {
    const uint32_t muted = seenMuted_;
    for (int i = 0; i < kLayers; i++) {
      Layer &layer = layers_[i];
      if (layer.count == 0 || (muted & (1u << i))) continue;
      for (int e = 0; e < layer.count; e++) {
        const Event &event = layer.events[e];
        if (event.beat < from || event.beat >= to) continue;
        // What is being played right now is already heard live.
        if (i == recording_ && event.pass == pass_) continue;
        layer.engine->handleMidi(event.status, event.data1, event.data2);
      }
    }
  }

  void renderLayers(float *left, float *right, int frames) {
    float l[N], r[N];
    int done = 0;
    while (done < frames) {
      const int count = std::min(frames - done, (int)N);
      for (auto &layer : layers_) {
        if (layer.count == 0 && layer.engine->activeVoices() == 0 && tailFrames_ <= 0 && !layer.hasContent) continue;
        layer.engine->render(l, r, count);
        for (int i = 0; i < count; i++) {
          left[done + i] += l[i];
          right[done + i] += r[i];
        }
      }
      done += count;
    }
  }

  void startClick(bool accent) {
    clickPhase_ = 0;
    clickLevel_ = accent ? 0.32f : 0.2f;
    clickStep_ = (accent ? 1760.0f : 1175.0f) * 6.2831853f / (float)sampleRate_;
  }

  void renderClick(float *left, float *right, int frames) {
    if (clickLevel_ < 0.0005f) return;
    const float decay = std::exp(-1.0f / (0.012f * (float)sampleRate_));
    for (int i = 0; i < frames; i++) {
      const float s = std::sin(clickPhase_) * clickLevel_;
      clickPhase_ += clickStep_;
      clickLevel_ *= decay;
      left[i] += s;
      right[i] += s;
    }
  }

  void publish() {
    uint32_t content = 0;
    for (int i = 0; i < kLayers; i++) {
      if (layers_[i].hasContent) content |= 1u << i;
    }
    stateContent_.store(content, std::memory_order_relaxed);
    statePhase_.store(phase_, std::memory_order_relaxed);
    stateRecording_.store(recording_, std::memory_order_relaxed);
    stateArmed_.store(armed_, std::memory_order_relaxed);
    statePosition_.store(position_, std::memory_order_relaxed);
  }

  // Shared.
  std::atomic<float> bpm_{112.0f};
  std::atomic<int> bars_{2};
  std::atomic<bool> metronome_{false};
  std::atomic<bool> quantize_{true};
  std::atomic<int> requestPlay_{-1};
  std::atomic<int> requestRecord_{-1};
  std::atomic<uint32_t> requestClear_{0};
  std::atomic<uint32_t> muted_{0};
  std::atomic<int> statePhase_{kStopped};
  std::atomic<int> stateRecording_{-1};
  std::atomic<int> stateArmed_{-1};
  std::atomic<double> statePosition_{0};
  std::atomic<uint32_t> stateContent_{0};

  // Render thread.
  Layer layers_[kLayers];
  double sampleRate_ = 48000;
  int phase_ = kStopped;
  double position_ = 0;  // beats; negative during the count-in
  long lastBeat_ = -100;
  uint32_t pass_ = 0;
  int recording_ = -1;
  int armed_ = -1;
  uint32_t seenMuted_ = 0;
  bool held_[128] = {};
  double shift_[128] = {};
  long tailFrames_ = 0;
  float clickPhase_ = 0, clickStep_ = 0, clickLevel_ = 0;
};

}  // namespace openfm

#endif  // OPENFM_LOOPER_H_

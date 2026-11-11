// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

#include "Engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>

#include "exp2.h"
#include "freqlut.h"
#include "pitchenv.h"
#include "sin.h"

namespace openfm {

namespace {

std::once_flag tablesOnce;

// MSFA sums voices in Q24-ish fixed point where one full-level carrier peaks
// at 2^25.
const float kOutputScale = 1.0f / (float)(1 << 26);

// Transparent below ~0.5, saturating smoothly towards +-1 above.
inline float softClip(float x) {
  const float a = std::fabs(x);
  if (a <= 0.5f) return x;
  const float y = 0.5f + (a - 0.5f) / (1.0f + (a - 0.5f) * 2.0f);
  return x < 0 ? -y : y;
}

}  // namespace

void Engine::initPatch(uint8_t patch[kPatchSize]) {
  std::memset(patch, 0, kPatchSize);
  for (int op = 0; op < 6; op++) {
    uint8_t *p = patch + op * 21;
    p[0] = p[1] = p[2] = p[3] = 99;   // EG rates
    p[4] = p[5] = p[6] = 99;          // EG levels 1-3
    p[7] = 0;                         // EG level 4
    p[8] = 39;                        // break point (C3)
    p[16] = op == 5 ? 99 : 0;         // only OP1 sounds
    p[18] = 1;                        // coarse 1.00
    p[20] = 7;                        // detune centre
  }
  for (int i = 0; i < 4; i++) {
    patch[126 + i] = 99;              // pitch EG rates
    patch[130 + i] = 50;              // pitch EG levels (centre)
  }
  patch[134] = 0;                     // algorithm 1
  patch[136] = 1;                     // oscillator key sync
  patch[137] = 35;                    // LFO speed
  patch[141] = 1;                     // LFO sync
  patch[142] = 0;                     // LFO triangle
  patch[143] = 3;                     // pitch mod sensitivity
  patch[144] = 24;                    // transpose: concert pitch
  const char *name = "INIT VOICE";
  std::memcpy(patch + 145, name, 10);
  patch[155] = 0x3f;                  // all operators on
}

Engine::Engine() {
  uint8_t init[kPatchSize];
  initPatch(init);
  for (int i = 0; i < kPatchSize; i++) pending_[i].store(init[i]);
  std::memcpy(patch_, init, kPatchSize);
  fx_[kChorusMix].store(0.0f);
  fx_[kChorusRate].store(0.6f);
  fx_[kChorusDepth].store(0.5f);
  fx_[kDelayMix].store(0.0f);
  fx_[kDelayTime].store(0.35f);
  fx_[kDelayFeedback].store(0.35f);
  fx_[kReverbMix].store(0.2f);
  fx_[kReverbSize].store(0.5f);
  fx_[kReverbDamp].store(0.4f);
  fx_[kVolume].store(0.8f);
  fx_[kBendRange].store(2.0f);
  fx_[kMono].store(0.0f);
  fx_[kGlide].store(0.06f);
  fx_[kArpMode].store(0.0f);
  fx_[kArpRate].store(1.0f);
  fx_[kTempo].store(112.0f);
  std::memset(scope_, 0, sizeof(scope_));
  std::memset(block_, 0, sizeof(block_));
}

void Engine::prepare(double sampleRate) {
  std::call_once(tablesOnce, [] {
    Exp2::init();
    Tanh::init();
    Sin::init();
  });
  // These tables are process-wide: every engine in a process must run at the
  // same sample rate.
  Freqlut::init(sampleRate);
  Lfo::init(sampleRate);
  PitchEnv::init(sampleRate);
  Env::init_sr(sampleRate);

  chorus_.prepare(sampleRate);
  delay_.prepare(sampleRate);
  reverb_.prepare(sampleRate);

  for (auto &slot : slots_) slot = Slot();
  sampleRate_ = sampleRate;
  clearHeld();
  lfo_ = Lfo();
  lfo_.reset((const char *)patch_ + 137);
  seenGeneration_ = 0;
  blockPos_ = N;
  volume_ = fx_[kVolume].load();
  prepared_ = true;
}

void Engine::setParam(int index, int value) {
  if (index < 0 || index >= kPatchSize) return;
  pending_[index].store((uint8_t)std::clamp(value, 0, 127), std::memory_order_relaxed);
  generation_.fetch_add(1, std::memory_order_release);
}

int Engine::param(int index) const {
  if (index < 0 || index >= kPatchSize) return 0;
  return pending_[index].load(std::memory_order_relaxed);
}

void Engine::loadPatch(const uint8_t patch[kPatchSize]) {
  for (int i = 0; i < kPatchSize; i++) {
    pending_[i].store(patch[i], std::memory_order_relaxed);
  }
  generation_.fetch_add(1, std::memory_order_release);
}

void Engine::copyPatch(uint8_t patch[kPatchSize]) const {
  for (int i = 0; i < kPatchSize; i++) {
    patch[i] = pending_[i].load(std::memory_order_relaxed);
  }
}

void Engine::setFx(int id, float value) {
  if (id < 0 || id >= kFxCount) return;
  fx_[id].store(value, std::memory_order_relaxed);
}

float Engine::fx(int id) const {
  if (id < 0 || id >= kFxCount) return 0;
  return fx_[id].load(std::memory_order_relaxed);
}

bool Engine::pushEvent(Queue queue, uint8_t status, uint8_t data1, uint8_t data2) {
  EventQueue &q = queues_[queue];
  const uint32_t head = q.head.load(std::memory_order_relaxed);
  const uint32_t next = (head + 1) % EventQueue::kSize;
  if (next == q.tail.load(std::memory_order_acquire)) return false;  // full
  q.items[head] = (uint32_t)status | ((uint32_t)data1 << 8) | ((uint32_t)data2 << 16);
  q.head.store(next, std::memory_order_release);
  return true;
}

void Engine::panic() { panic_.store(true, std::memory_order_release); }

void Engine::drainQueues() {
  for (auto &q : queues_) {
    uint32_t tail = q.tail.load(std::memory_order_relaxed);
    const uint32_t head = q.head.load(std::memory_order_acquire);
    while (tail != head) {
      const uint32_t e = q.items[tail];
      handleMidi(e & 0xff, (e >> 8) & 0xff, (e >> 16) & 0xff);
      tail = (tail + 1) % EventQueue::kSize;
    }
    q.tail.store(tail, std::memory_order_release);
  }
}

void Engine::handleMidi(uint8_t status, uint8_t data1, uint8_t data2) {
  switch (status & 0xf0) {
    case 0x80:
      keyUp(data1 & 0x7f);
      break;
    case 0x90:
      if (data2 == 0) keyUp(data1 & 0x7f);
      else keyDown(data1 & 0x7f, data2 & 0x7f);
      break;
    case 0xb0:
      switch (data1) {
        case 1:
          mod_.modWheel = data2 & 0x7f;
          break;
        case 64: {
          const bool down = data2 >= 64;
          if (sustain_ && !down) {
            for (auto &slot : slots_) {
              if (slot.active && slot.sustained) {
                slot.sustained = false;
                slot.voice.keyup();
              }
            }
          }
          sustain_ = down;
          break;
        }
        case 120:
        case 123:
          allNotesOff();
          break;
        default:
          break;
      }
      break;
    case 0xe0:
      bend_ = (data1 & 0x7f) | ((data2 & 0x7f) << 7);
      break;
    default:
      break;
  }
}

void Engine::clearHeld() {
  monoCount_ = 0;
  monoSlot_ = -1;
  arpCount_ = 0;
  arpNote_ = -1;
  arpFresh_ = true;
}

// MARK: Arpeggiator

void Engine::keyDown(int note, int velocity) {
  if (fx_[kArpMode].load(std::memory_order_relaxed) < 0.5f) {
    playNote(note, velocity);
    return;
  }
  // Keep the held keys sorted, lowest first.
  int at = 0;
  while (at < arpCount_ && arp_[at].note < note) at++;
  if (at < arpCount_ && arp_[at].note == note) {
    arp_[at].velocity = (uint8_t)velocity;
    return;
  }
  if (arpCount_ == kMaxHeld) return;
  for (int i = arpCount_; i > at; i--) arp_[i] = arp_[i - 1];
  arp_[at] = {(uint8_t)note, (uint8_t)velocity};
  if (arpCount_++ == 0) {
    // The first key sounds at once.
    arpFresh_ = true;
    arpCountdown_ = 0;
  } else if (at <= arpIndex_) {
    arpIndex_++;
  }
}

void Engine::keyUp(int note) {
  for (int i = 0; i < arpCount_; i++) {
    if (arp_[i].note != note) continue;
    for (int j = i; j < arpCount_ - 1; j++) arp_[j] = arp_[j + 1];
    arpCount_--;
    if (i < arpIndex_) arpIndex_--;
    if (arpCount_ == 0 && arpNote_ >= 0) {
      releaseNote(arpNote_);
      arpNote_ = -1;
    }
    return;
  }
  releaseNote(note);
}

void Engine::stepArp() {
  if (arpCount_ == 0) return;
  const int mode = (int)std::lround(fx_[kArpMode].load(std::memory_order_relaxed));
  if (mode == 0) {
    // Switched off with keys down: let go.
    if (arpNote_ >= 0) releaseNote(arpNote_);
    arpNote_ = -1;
    arpCount_ = 0;
    return;
  }
  if (arpNote_ >= 0) {
    arpGate_ -= N;
    if (arpGate_ <= 0) {
      releaseNote(arpNote_);
      arpNote_ = -1;
    }
  }
  arpCountdown_ -= N;
  if (arpCountdown_ > 0) return;

  const double tempo = std::clamp((double)fx_[kTempo].load(std::memory_order_relaxed), 40.0, 240.0);
  const int perBeat = std::clamp((int)std::lround(fx_[kArpRate].load(std::memory_order_relaxed)), 0, 3) + 1;
  const double step = sampleRate_ * 60.0 / tempo / perBeat;
  arpCountdown_ = arpCountdown_ < -step ? step : arpCountdown_ + step;

  const int last = arpCount_ - 1;
  if (arpFresh_) {
    arpFresh_ = false;
    arpIndex_ = mode == 2 ? last : 0;
    arpDirection_ = 1;
  } else if (mode == 1) {
    arpIndex_ = arpIndex_ >= last ? 0 : arpIndex_ + 1;
  } else if (mode == 2) {
    arpIndex_ = arpIndex_ <= 0 ? last : std::min(arpIndex_ - 1, last);
  } else if (last == 0) {
    arpIndex_ = 0;
  } else {
    if (arpIndex_ >= last) arpDirection_ = -1;
    else if (arpIndex_ <= 0) arpDirection_ = 1;
    arpIndex_ = std::clamp(arpIndex_ + arpDirection_, 0, last);
  }
  if (arpNote_ >= 0) releaseNote(arpNote_);
  arpNote_ = arp_[arpIndex_].note;
  arpGate_ = step * 0.6;
  playNote(arpNote_, arp_[arpIndex_].velocity);
}

// MARK: Mono

void Engine::playNote(int note, int velocity) {
  if (fx_[kMono].load(std::memory_order_relaxed) < 0.5f) {
    startNote(note, velocity);
    return;
  }
  for (int i = 0; i < monoCount_; i++) {
    if (mono_[i].note != note) continue;
    for (int j = i; j < monoCount_ - 1; j++) mono_[j] = mono_[j + 1];
    monoCount_--;
    break;
  }
  if (monoCount_ == kMaxHeld) {
    for (int j = 0; j < monoCount_ - 1; j++) mono_[j] = mono_[j + 1];
    monoCount_--;
  }
  mono_[monoCount_++] = {(uint8_t)note, (uint8_t)velocity};

  const bool legato = monoSlot_ >= 0 && slots_[monoSlot_].active && slots_[monoSlot_].keyDown;
  if (legato) {
    const float seconds = fx_[kGlide].load(std::memory_order_relaxed);
    Slot &slot = slots_[monoSlot_];
    slot.voice.glideTo(patch_, note, (int)(seconds * sampleRate_ / N));
    slot.note = note;
  } else {
    monoSlot_ = startNote(note, velocity);
  }
}

void Engine::releaseNote(int note) {
  for (int i = 0; i < monoCount_; i++) {
    if (mono_[i].note != note) continue;
    for (int j = i; j < monoCount_ - 1; j++) mono_[j] = mono_[j + 1];
    monoCount_--;
    const bool sounding = monoSlot_ >= 0 && slots_[monoSlot_].active &&
                          slots_[monoSlot_].keyDown && slots_[monoSlot_].note == note;
    if (!sounding) return;
    if (monoCount_ > 0) {
      // Fall back to the key still held.
      const float seconds = fx_[kGlide].load(std::memory_order_relaxed);
      Slot &slot = slots_[monoSlot_];
      slot.note = mono_[monoCount_ - 1].note;
      slot.voice.glideTo(patch_, slot.note, (int)(seconds * sampleRate_ / N));
    } else {
      stopNote(note);
      monoSlot_ = -1;
    }
    return;
  }
  stopNote(note);
}

// MARK: Voices

int Engine::startNote(int note, int velocity) {
  Slot *target = nullptr;
  // Retrigger a voice already playing this note.
  for (auto &slot : slots_) {
    if (slot.active && slot.note == note) { target = &slot; break; }
  }
  if (!target) {
    for (auto &slot : slots_) {
      if (!slot.active) { target = &slot; break; }
    }
  }
  if (!target) {
    // Steal the oldest released voice, otherwise the oldest voice.
    Slot *oldestReleased = nullptr;
    Slot *oldest = &slots_[0];
    for (auto &slot : slots_) {
      if (slot.age < oldest->age) oldest = &slot;
      if (!slot.keyDown && !slot.sustained &&
          (!oldestReleased || slot.age < oldestReleased->age)) {
        oldestReleased = &slot;
      }
    }
    target = oldestReleased ? oldestReleased : oldest;
  }
  lfo_.keydown();
  target->voice.init(patch_, note, velocity, !target->active);
  target->active = true;
  target->keyDown = true;
  target->sustained = false;
  target->note = note;
  target->age = ++clock_;
  return (int)(target - slots_);
}

void Engine::stopNote(int note) {
  for (auto &slot : slots_) {
    if (slot.active && slot.keyDown && slot.note == note) {
      slot.keyDown = false;
      if (sustain_) slot.sustained = true;
      else slot.voice.keyup();
    }
  }
}

void Engine::allNotesOff() {
  sustain_ = false;
  clearHeld();
  for (auto &slot : slots_) {
    if (slot.active && (slot.keyDown || slot.sustained)) slot.voice.keyup();
    slot.keyDown = false;
    slot.sustained = false;
  }
}

void Engine::syncParams() {
  const uint32_t generation = generation_.load(std::memory_order_acquire);
  if (generation == seenGeneration_) return;
  seenGeneration_ = generation;
  bool lfoChanged = false;
  for (int i = 0; i < kPatchSize; i++) {
    const uint8_t v = pending_[i].load(std::memory_order_relaxed);
    if (v != patch_[i]) {
      patch_[i] = v;
      if (i >= 137 && i <= 142) lfoChanged = true;
    }
  }
  if (lfoChanged) lfo_.reset((const char *)patch_ + 137);
  for (auto &slot : slots_) {
    if (slot.active) slot.voice.update(patch_);
  }
}

void Engine::computeBlock() {
  syncParams();
  stepArp();

  mod_.lfoValue = lfo_.getsample();
  mod_.lfoDelay = lfo_.getdelay();
  const float range = fx_[kBendRange].load(std::memory_order_relaxed);
  const float semis = (float)(bend_ - 0x2000) / 8192.0f * range;
  mod_.pitchBend = (int32_t)(semis * (float)(1 << 24) / 12.0f);

  alignas(16) int32_t buf[N];
  std::memset(buf, 0, sizeof(buf));
  int active = 0;
  for (auto &slot : slots_) {
    if (!slot.active) continue;
    slot.voice.compute(buf, mod_);
    if (slot.voice.finished()) slot.active = false;
    else active++;
  }
  activeVoices_.store(active, std::memory_order_relaxed);
  for (int i = 0; i < N; i++) block_[i] = (float)buf[i] * kOutputScale;
  blockPos_ = 0;
}

void Engine::render(float *left, float *right, int frames) {
  if (!prepared_) {
    std::memset(left, 0, sizeof(float) * (size_t)frames);
    std::memset(right, 0, sizeof(float) * (size_t)frames);
    return;
  }
  if (panic_.exchange(false, std::memory_order_acq_rel)) {
    for (auto &slot : slots_) slot = Slot();
    sustain_ = false;
    clearHeld();
  }
  drainQueues();

  int done = 0;
  while (done < frames) {
    if (blockPos_ == N) computeBlock();
    const int count = std::min(frames - done, N - blockPos_);
    std::memcpy(left + done, block_ + blockPos_, sizeof(float) * (size_t)count);
    std::memcpy(right + done, block_ + blockPos_, sizeof(float) * (size_t)count);
    blockPos_ += count;
    done += count;
  }

  chorus_.process(left, right, frames,
                  fx_[kChorusMix].load(std::memory_order_relaxed),
                  fx_[kChorusRate].load(std::memory_order_relaxed),
                  fx_[kChorusDepth].load(std::memory_order_relaxed));
  delay_.process(left, right, frames,
                 fx_[kDelayMix].load(std::memory_order_relaxed),
                 fx_[kDelayTime].load(std::memory_order_relaxed),
                 std::min(0.95f, fx_[kDelayFeedback].load(std::memory_order_relaxed)));
  reverb_.process(left, right, frames,
                  fx_[kReverbMix].load(std::memory_order_relaxed),
                  fx_[kReverbSize].load(std::memory_order_relaxed),
                  fx_[kReverbDamp].load(std::memory_order_relaxed));

  const float v = fx_[kVolume].load(std::memory_order_relaxed);
  const float target = v * v * 2.0f;
  uint32_t w = scopeWrite_.load(std::memory_order_relaxed);
  for (int i = 0; i < frames; i++) {
    volume_ += (target - volume_) * 0.002f;
    left[i] = softClip(left[i] * volume_);
    right[i] = softClip(right[i] * volume_);
    scope_[w] = 0.5f * (left[i] + right[i]);
    w = (w + 1) % kScopeSize;
  }
  scopeWrite_.store(w, std::memory_order_release);
}

void Engine::copyScope(float *dst, int count) const {
  count = std::min(count, (int)kScopeSize);
  const uint32_t w = scopeWrite_.load(std::memory_order_acquire);
  uint32_t r = (w + kScopeSize - (uint32_t)count) % kScopeSize;
  for (int i = 0; i < count; i++) {
    dst[i] = scope_[r];
    r = (r + 1) % kScopeSize;
  }
}

}  // namespace openfm

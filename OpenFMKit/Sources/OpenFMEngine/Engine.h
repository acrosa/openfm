// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0
//
// The OpenFM synthesis engine: 16 six-operator FM voices (MSFA), a DX7
// compatible LFO, MIDI handling and the effect chain. One instance is shared
// by the standalone app and the AUv3 extension through OpenFMAudioUnit.
//
// Threading contract
//   prepare()                         any non-realtime thread, before render
//   setParam / loadPatch / setFx      any thread, wait-free
//   pushEvent(queue, ...)             one producer thread per queue, wait-free
//   handleMidi() / render()           the render thread only
//   copyScope / activeVoices          any thread (visualisation only)
//
// render() never allocates, locks or blocks.

#ifndef OPENFM_ENGINE_H_
#define OPENFM_ENGINE_H_

#include <atomic>
#include <cstdint>

#include "Effects.h"
#include "Voice.h"
#include "lfo.h"

namespace openfm {

class Engine {
 public:
  static constexpr int kPatchSize = 156;
  static constexpr int kMaxVoices = 16;
  static constexpr int kScopeSize = 4096;

  enum Fx {
    kChorusMix = 0,   // 0..1
    kChorusRate,      // Hz
    kChorusDepth,     // 0..1
    kDelayMix,        // 0..1
    kDelayTime,       // seconds
    kDelayFeedback,   // 0..0.95
    kReverbMix,       // 0..1
    kReverbSize,      // 0..1
    kReverbDamp,      // 0..1
    kVolume,          // 0..1
    kBendRange,       // semitones
    kMono,            // 0 poly, 1 one voice with legato
    kGlide,           // seconds a legato note takes to arrive (mono)
    kArpMode,         // 0 off, 1 up, 2 down, 3 up and down
    kArpRate,         // 0..3: 1, 2, 3 or 4 steps per beat
    kTempo,           // beats per minute, for the arpeggiator
    kFxCount
  };

  enum Queue { kQueueUI = 0, kQueueMIDI = 1, kQueueCount };

  Engine();

  void prepare(double sampleRate);

  // Voice parameters: unpacked DX7 voice layout, index 0..155.
  void setParam(int index, int value);
  int param(int index) const;
  void loadPatch(const uint8_t patch[kPatchSize]);
  void copyPatch(uint8_t patch[kPatchSize]) const;

  void setFx(int id, float value);
  float fx(int id) const;

  // Queue a 3-byte MIDI message from a non-realtime thread.
  bool pushEvent(Queue queue, uint8_t status, uint8_t data1, uint8_t data2);
  // Release everything at the start of the next render.
  void panic();

  void handleMidi(uint8_t status, uint8_t data1, uint8_t data2);
  void render(float *left, float *right, int frames);

  // Copies the most recent `count` output samples (oldest first).
  void copyScope(float *dst, int count) const;
  int activeVoices() const { return activeVoices_.load(std::memory_order_relaxed); }

  static void initPatch(uint8_t patch[kPatchSize]);

 private:
  struct Slot {
    Voice voice;
    bool active = false;
    bool keyDown = false;
    bool sustained = false;
    int note = 0;
    uint64_t age = 0;
  };

  struct EventQueue {
    static constexpr uint32_t kSize = 256;
    std::atomic<uint32_t> head{0};
    std::atomic<uint32_t> tail{0};
    uint32_t items[kSize];
  };

  void drainQueues();
  void syncParams();
  void computeBlock();
  // Keys arrive at keyDown/keyUp, pass through the arpeggiator, then the
  // mono note stack, and reach the voices at startNote/stopNote.
  void keyDown(int note, int velocity);
  void keyUp(int note);
  void stepArp();
  void playNote(int note, int velocity);
  void releaseNote(int note);
  int startNote(int note, int velocity);
  void stopNote(int note);
  void allNotesOff();
  void clearHeld();

  // Shared with other threads.
  std::atomic<uint8_t> pending_[kPatchSize];
  std::atomic<uint32_t> generation_{1};
  std::atomic<float> fx_[kFxCount];
  std::atomic<bool> panic_{false};
  std::atomic<int> activeVoices_{0};
  EventQueue queues_[kQueueCount];
  float scope_[kScopeSize];
  std::atomic<uint32_t> scopeWrite_{0};

  // Render thread only.
  uint8_t patch_[kPatchSize];
  uint32_t seenGeneration_ = 0;
  Slot slots_[kMaxVoices];
  Lfo lfo_{};
  VoiceMod mod_;
  uint64_t clock_ = 0;
  bool sustain_ = false;
  int bend_ = 0x2000;
  double sampleRate_ = 44100.0;

  static constexpr int kMaxHeld = 16;
  struct Held { uint8_t note; uint8_t velocity; };
  // Mono: keys held, most recent last, and the slot that is sounding.
  Held mono_[kMaxHeld];
  int monoCount_ = 0;
  int monoSlot_ = -1;
  // Arpeggiator: keys held, lowest first.
  Held arp_[kMaxHeld];
  int arpCount_ = 0;
  int arpIndex_ = 0;
  int arpDirection_ = 1;
  bool arpFresh_ = true;
  int arpNote_ = -1;          // note sounding now, or -1
  double arpCountdown_ = 0;   // samples until the next step
  double arpGate_ = 0;        // samples until the sounding note is let go

  float block_[N];
  int blockPos_ = N;
  float volume_ = 0.0f;

  Chorus chorus_;
  Delay delay_;
  Reverb reverb_;
  bool prepared_ = false;
};

}  // namespace openfm

#endif  // OPENFM_ENGINE_H_

/*
 * Copyright 2012 Google Inc.
 * Copyright 2026 The OpenFM Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// One six-operator FM voice. Derived from MSFA's dx7note.{h,cc}; OpenFM adds
// live parameter updates, LFO amplitude modulation, mod wheel, configurable
// pitch bend, transpose, oscillator key sync, operator on/off and
// end-of-note detection.

#ifndef OPENFM_VOICE_H_
#define OPENFM_VOICE_H_

#include <cstdint>

#include "synth.h"
#include "env.h"
#include "pitchenv.h"
#include "fm_core.h"

namespace openfm {

// Per-block modulation shared by every voice.
struct VoiceMod {
  int32_t lfoValue = 1 << 23;  // 0..1 in Q24
  int32_t lfoDelay = 0;        // 0..1 in Q24
  int32_t pitchBend = 0;       // octaves in Q24
  int modWheel = 0;            // 0..127
};

class Voice {
 public:
  // `patch` is a 156-byte unpacked DX7 voice. Byte 155 is the operator
  // enable mask (bit n = operator slot n, slot 0 = OP6).
  void init(const uint8_t patch[156], int midinote, int velocity, bool wasIdle);

  // Moves a sounding note to another key without restarting its envelopes,
  // sliding there over `blocks` render blocks (0 jumps).
  void glideTo(const uint8_t patch[156], int midinote, int blocks);

  // Re-read every parameter while the note keeps sounding.
  void update(const uint8_t patch[156]);

  // Adds N samples to `buf`.
  void compute(int32_t *buf, const VoiceMod &mod);

  void keyup();

  // True once the note has been released and every carrier has finished.
  bool finished() const;

 private:
  void configure(const uint8_t patch[156], bool start);

  FmCore core_;
  Env env_[6];
  FmOpParams params_[6];
  PitchEnv pitchenv_;
  int32_t basepitch_[6];
  int32_t fb_buf_[2];
  int32_t fb_shift_;

  int algorithm_;
  int pitchmoddepth_;
  int pitchmodsens_;
  int ampmoddepth_;
  int32_t ampmodsens_[6];
  bool fixed_[6];
  bool enabled_[6];

  int32_t glide_ = 0;       // pitch still to travel, octaves in Q24
  int32_t glideStep_ = 0;   // per block

  int midinote_;
  int velocity_;
  bool down_;
};

}  // namespace openfm

#endif  // OPENFM_VOICE_H_

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

// Derived from MSFA's dx7note.cc. See Voice.h for the list of changes.

#include <math.h>
#include <algorithm>

#include "Voice.h"
#include "freqlut.h"
#include "exp2.h"

namespace openfm {

namespace {

int32_t midinote_to_logfreq(int midinote) {
  const int base = 50857777;  // (1 << 24) * (log(440) / log(2) - 69/12)
  const int step = (1 << 24) / 12;
  return base + step * midinote;
}

const int32_t coarsemul[] = {
  -16777216, 0, 16777216, 26591258, 33554432, 38955489, 43368474, 47099600,
  50331648, 53182516, 55732705, 58039632, 60145690, 62083076, 63876816,
  65546747, 67108864, 68576247, 69959732, 71268397, 72509921, 73690858,
  74816848, 75892776, 76922906, 77910978, 78860292, 79773775, 80654032,
  81503396, 82323963, 83117622
};

int32_t osc_freq(int midinote, int mode, int coarse, int fine, int detune) {
  int32_t logfreq;
  if (mode == 0) {
    logfreq = midinote_to_logfreq(midinote);
    logfreq += coarsemul[coarse & 31];
    if (fine) {
      // (1 << 24) / log(2)
      logfreq += (int32_t)floor(24204406.323123 * log(1 + 0.01 * fine) + 0.5);
    }
    // This was measured at 7.213Hz per count at 9600Hz, but the exact
    // value is somewhat dependent on midinote. Close enough for now.
    logfreq += 12606 * (detune - 7);
  } else {
    // ((1 << 24) * log(10) / log(2) * .01) << 3
    logfreq = (4458616 * ((coarse & 3) * 100 + fine)) >> 3;
    logfreq += detune > 7 ? 13457 * (detune - 7) : 0;
  }
  return logfreq;
}

const uint8_t velocity_data[64] = {
  0, 70, 86, 97, 106, 114, 121, 126, 132, 138, 142, 148, 152, 156, 160, 163,
  166, 170, 173, 174, 178, 181, 184, 186, 189, 190, 194, 196, 198, 200, 202,
  205, 206, 209, 211, 214, 216, 218, 220, 222, 224, 225, 227, 229, 230, 232,
  233, 235, 237, 238, 240, 241, 242, 243, 244, 246, 246, 248, 249, 250, 251,
  252, 253, 254
};

// Returns velocity delta in microsteps.
int ScaleVelocity(int velocity, int sensitivity) {
  int clamped_vel = std::max(0, std::min(127, velocity));
  int vel_value = velocity_data[clamped_vel >> 1] - 239;
  int scaled_vel = ((sensitivity * vel_value + 7) >> 3) << 4;
  return scaled_vel;
}

int ScaleRate(int midinote, int sensitivity) {
  int x = std::min(31, std::max(0, midinote / 3 - 7));
  int qratedelta = (sensitivity * x) >> 3;
  return qratedelta;
}

const uint8_t exp_scale_data[] = {
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 14, 16, 19, 23, 27, 33, 39, 47, 56, 66,
  80, 94, 110, 126, 142, 158, 174, 190, 206, 222, 238, 250
};

int ScaleCurve(int group, int depth, int curve) {
  int scale;
  if (curve == 0 || curve == 3) {
    // linear
    scale = (group * depth * 329) >> 12;
  } else {
    // exponential
    int n_scale_data = sizeof(exp_scale_data);
    int raw_exp = exp_scale_data[std::min(group, n_scale_data - 1)];
    scale = (raw_exp * depth * 329) >> 15;
  }
  if (curve < 2) {
    scale = -scale;
  }
  return scale;
}

int ScaleLevel(int midinote, int break_pt, int left_depth, int right_depth,
    int left_curve, int right_curve) {
  int offset = midinote - break_pt - 17;
  if (offset >= 0) {
    return ScaleCurve(offset / 3, right_depth, right_curve);
  } else {
    return ScaleCurve((-offset) / 3, left_depth, left_curve);
  }
}

const uint8_t pitchmodsenstab[] = {
  0, 10, 20, 33, 55, 92, 153, 255
};

// Amplitude modulation sensitivity 0..3 as a Q24 fraction of full depth.
const int32_t ampmodsenstab[] = {
  0, 4362076, 7214203, 16777216
};

// Full-depth tremolo attenuates by this many doublings (6 dB each).
const int kAmpModDoublings = 6;

const int kLevelThresh = 1120;

}  // namespace

void Voice::configure(const uint8_t patch[156], bool start) {
  int rates[4];
  int levels[4];
  // Transpose: 24 is concert pitch, one unit per semitone.
  int pitchnote = midinote_ + (int)patch[144] - 24;
  int enableMask = patch[155];
  for (int op = 0; op < 6; op++) {
    int off = op * 21;
    for (int i = 0; i < 4; i++) {
      rates[i] = std::min<int>(99, patch[off + i]);
      levels[i] = std::min<int>(99, patch[off + 4 + i]);
    }
    int outlevel = std::min<int>(99, patch[off + 16]);
    outlevel = Env::scaleoutlevel(outlevel);
    int level_scaling = ScaleLevel(midinote_, patch[off + 8], patch[off + 9],
        patch[off + 10], patch[off + 11] & 3, patch[off + 12] & 3);
    outlevel += level_scaling;
    outlevel = std::min(127, outlevel);
    outlevel = outlevel << 5;
    outlevel += ScaleVelocity(velocity_, patch[off + 15] & 7);
    outlevel = std::max(0, outlevel);
    int rate_scaling = ScaleRate(midinote_, patch[off + 13] & 7);
    if (start) {
      env_[op].init(rates, levels, outlevel, rate_scaling);
    } else {
      env_[op].update(rates, levels, outlevel, rate_scaling);
    }

    int mode = patch[off + 17] & 1;
    int coarse = patch[off + 18] & 31;
    int fine = std::min<int>(99, patch[off + 19]);
    int detune = std::min<int>(14, patch[off + 20]);
    basepitch_[op] = osc_freq(pitchnote, mode, coarse, fine, detune);
    fixed_[op] = mode != 0;
    ampmodsens_[op] = ampmodsenstab[patch[off + 14] & 3];
    enabled_[op] = (enableMask >> op) & 1;
  }
  if (start) {
    for (int i = 0; i < 4; i++) {
      rates[i] = std::min<int>(99, patch[126 + i]);
      levels[i] = std::min<int>(99, patch[130 + i]);
    }
    pitchenv_.set(rates, levels);
  }
  algorithm_ = patch[134] & 31;
  int feedback = patch[135] & 7;
  fb_shift_ = feedback != 0 ? 8 - feedback : 16;
  pitchmoddepth_ = (std::min<int>(99, patch[139]) * 165) >> 6;
  ampmoddepth_ = std::min<int>(99, patch[140]);
  pitchmodsens_ = pitchmodsenstab[patch[143] & 7];
}

void Voice::init(const uint8_t patch[156], int midinote, int velocity,
                 bool wasIdle) {
  midinote_ = midinote;
  velocity_ = velocity;
  down_ = true;
  glide_ = 0;
  glideStep_ = 0;
  bool keySync = patch[136] != 0;
  for (int op = 0; op < 6; op++) {
    if (keySync || wasIdle) {
      params_[op].phase = 0;
    }
    params_[op].gain[0] = 0;
    params_[op].gain[1] = 0;
  }
  if (wasIdle) {
    fb_buf_[0] = 0;
    fb_buf_[1] = 0;
  }
  configure(patch, true);
}

void Voice::glideTo(const uint8_t patch[156], int midinote, int blocks) {
  // Keep sounding where the pitch is now, then close the distance.
  glide_ += (midinote_ - midinote) * ((1 << 24) / 12);
  midinote_ = midinote;
  const int32_t distance = glide_ < 0 ? -glide_ : glide_;
  glideStep_ = blocks > 0 ? std::max<int32_t>(1, distance / blocks) : distance;
  configure(patch, false);
}

void Voice::update(const uint8_t patch[156]) {
  configure(patch, false);
}

void Voice::compute(int32_t *buf, const VoiceMod &mod) {
  int32_t pitchmod = pitchenv_.getsample();

  // LFO pitch modulation: the patch depth fades in with the LFO delay, the
  // mod wheel adds depth immediately.
  int64_t pmd = (int64_t)pitchmoddepth_ * (int64_t)mod.lfoDelay;  // Q32
  pmd += ((int64_t)mod.modWheel * 2) << 24;
  pmd = std::min<int64_t>(pmd, (int64_t)255 << 24);
  int32_t senslfo = pitchmodsens_ * (mod.lfoValue - (1 << 23));
  pitchmod += (int32_t)((pmd * (int64_t)senslfo) >> 39);

  // LFO amplitude modulation, as an attenuation in Q24 doublings.
  int64_t amdepth = ((int64_t)ampmoddepth_ * (int64_t)mod.lfoDelay) / 99;
  int64_t amod = (((int64_t)(1 << 24) - mod.lfoValue) * amdepth) >> 24;

  int32_t pitchKeyed = pitchmod + mod.pitchBend + glide_;
  if (glide_ > 0) glide_ = std::max(0, glide_ - glideStep_);
  else if (glide_ < 0) glide_ = std::min(0, glide_ + glideStep_);
  for (int op = 0; op < 6; op++) {
    params_[op].gain[0] = params_[op].gain[1];
    int32_t level = env_[op].getsample();
    if (ampmodsens_[op] != 0) {
      level -= (int32_t)((amod * ampmodsens_[op]) >> 24) * kAmpModDoublings;
      level = std::max(level, 0);
    }
    int32_t gain = enabled_[op] ? Exp2::lookup(level - (14 * (1 << 24))) : 0;
    // Fixed-frequency operators ignore the keyboard, and so the bender.
    params_[op].freq =
        Freqlut::lookup(basepitch_[op] + (fixed_[op] ? pitchmod : pitchKeyed));
    params_[op].gain[1] = gain;
  }
  core_.compute(buf, params_, algorithm_, fb_buf_, fb_shift_);
}

void Voice::keyup() {
  down_ = false;
  for (int op = 0; op < 6; op++) {
    env_[op].keydown(false);
  }
  pitchenv_.keydown(false);
}

bool Voice::finished() const {
  if (down_) return false;
  bool silent = true;
  bool released = true;
  for (int op = 0; op < 6; op++) {
    if (!enabled_[op] || !FmCore::isCarrier(algorithm_, op)) continue;
    if (params_[op].gain[1] >= kLevelThresh) silent = false;
    if (!env_[op].done()) released = false;
  }
  return silent || released;
}

}  // namespace openfm

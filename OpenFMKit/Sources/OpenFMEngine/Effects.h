// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0
//
// Chorus, delay and reverb. All memory is allocated in prepare(); process()
// never allocates, locks or blocks.

#ifndef OPENFM_EFFECTS_H_
#define OPENFM_EFFECTS_H_

#include <cmath>
#include <cstddef>
#include <vector>

namespace openfm {

class DelayLine {
 public:
  void prepare(int minSamples) {
    int size = 16;
    while (size < minSamples + 4) size <<= 1;
    buf_.assign((size_t)size, 0.0f);
    mask_ = size - 1;
    w_ = 0;
  }
  void clear() { std::fill(buf_.begin(), buf_.end(), 0.0f); }
  inline void write(float x) {
    buf_[(size_t)w_] = x;
    w_ = (w_ + 1) & mask_;
  }
  // Sample written `d` writes ago (d >= 1).
  inline float tap(int d) const { return buf_[(size_t)((w_ - d) & mask_)]; }
  // Fractional tap with linear interpolation.
  inline float tap(float d) const {
    int i = (int)d;
    float f = d - (float)i;
    float a = buf_[(size_t)((w_ - i) & mask_)];
    float b = buf_[(size_t)((w_ - i - 1) & mask_)];
    return a + (b - a) * f;
  }

 private:
  std::vector<float> buf_;
  int mask_ = 0;
  int w_ = 0;
};

// Two modulated delay lines a quarter cycle apart: a mono source comes out
// wide.
class Chorus {
 public:
  void prepare(double sampleRate) {
    sr_ = (float)sampleRate;
    left_.prepare((int)(0.05 * sampleRate));
    right_.prepare((int)(0.05 * sampleRate));
    phase_ = 0;
  }
  void process(float *l, float *r, int n, float mix, float rateHz, float depth) {
    const float inc = rateHz / sr_;
    const float base = 0.007f * sr_;
    const float span = 0.006f * sr_ * depth;
    const float wet = 0.5f * mix;
    const float dry = 1.0f - wet;
    for (int i = 0; i < n; i++) {
      phase_ += inc;
      if (phase_ >= 1.0f) phase_ -= 1.0f;
      const float a = 6.2831853f * phase_;
      const float ml = 0.5f + 0.5f * std::sin(a);
      const float mr = 0.5f + 0.5f * std::cos(a);
      left_.write(l[i]);
      right_.write(r[i]);
      const float wl = left_.tap(base + span * ml + 1.0f);
      const float wr = right_.tap(base + span * mr + 1.0f);
      l[i] = dry * l[i] + wet * wl;
      r[i] = dry * r[i] + wet * wr;
    }
  }

 private:
  DelayLine left_, right_;
  float sr_ = 48000;
  float phase_ = 0;
};

// Ping-pong delay with a gently darkened feedback path. Time changes glide
// like tape.
class Delay {
 public:
  static constexpr float kMaxSeconds = 1.5f;
  void prepare(double sampleRate) {
    sr_ = (float)sampleRate;
    left_.prepare((int)(kMaxSeconds * sampleRate) + 8);
    right_.prepare((int)(kMaxSeconds * sampleRate) + 8);
    time_ = 0.3f;
    lpL_ = lpR_ = 0;
  }
  void process(float *l, float *r, int n, float mix, float seconds, float feedback) {
    const float glide = 1.0f - std::exp(-1.0f / (0.08f * sr_));
    for (int i = 0; i < n; i++) {
      time_ += (seconds - time_) * glide;
      const float d = time_ * sr_ + 1.0f;
      const float outL = left_.tap(d);
      const float outR = right_.tap(d);
      lpL_ += (outL - lpL_) * 0.45f;
      lpR_ += (outR - lpR_) * 0.45f;
      const float in = 0.5f * (l[i] + r[i]);
      left_.write(in + lpR_ * feedback);
      right_.write(lpL_);
      l[i] += mix * outL;
      r[i] += mix * outR;
    }
  }

 private:
  DelayLine left_, right_;
  float sr_ = 48000;
  float time_ = 0.3f;
  float lpL_ = 0, lpR_ = 0;
};

// Eight-line feedback delay network with a Householder mixing matrix and
// per-line damping, fed through two allpass diffusers.
class Reverb {
 public:
  void prepare(double sampleRate) {
    sr_ = (float)sampleRate;
    static const int base[kLines] = {1117, 1361, 1559, 1789, 2053, 2311, 2609, 2903};
    for (int i = 0; i < kLines; i++) {
      len_[i] = (int)(base[i] * sampleRate / 48000.0);
      line_[i].prepare(len_[i] + 2);
      lp_[i] = 0;
    }
    apLen_[0] = (int)(0.0047 * sampleRate);
    apLen_[1] = (int)(0.0036 * sampleRate);
    ap_[0].prepare(apLen_[0] + 2);
    ap_[1].prepare(apLen_[1] + 2);
    lastSize_ = -1;
  }
  void process(float *l, float *r, int n, float mix, float size, float damp) {
    if (size != lastSize_) {
      lastSize_ = size;
      const float t60 = 0.3f + size * size * 11.7f;
      for (int i = 0; i < kLines; i++) {
        gain_[i] = std::pow(10.0f, -3.0f * (float)len_[i] / (t60 * sr_));
      }
    }
    const float k = 1.0f - (0.05f + 0.8f * damp);
    for (int i = 0; i < n; i++) {
      float x = 0.5f * (l[i] + r[i]);
      for (int a = 0; a < 2; a++) {
        const float d = ap_[a].tap(apLen_[a]);
        const float v = x + 0.6f * d;
        ap_[a].write(v);
        x = d - 0.6f * v;
      }
      float v[kLines];
      float sum = 0;
      for (int j = 0; j < kLines; j++) {
        const float o = line_[j].tap(len_[j]);
        lp_[j] += (o - lp_[j]) * k;
        v[j] = lp_[j] * gain_[j];
        sum += v[j];
      }
      sum *= 2.0f / kLines;
      for (int j = 0; j < kLines; j++) {
        line_[j].write(x + v[j] - sum);
      }
      const float wl = v[0] - v[2] + v[4] - v[6];
      const float wr = v[1] - v[3] + v[5] - v[7];
      l[i] += mix * 0.6f * wl;
      r[i] += mix * 0.6f * wr;
    }
  }

 private:
  static constexpr int kLines = 8;
  DelayLine line_[kLines];
  DelayLine ap_[2];
  int len_[kLines] = {};
  int apLen_[2] = {};
  float gain_[kLines] = {};
  float lp_[kLines] = {};
  float sr_ = 48000;
  float lastSize_ = -1;
};

}  // namespace openfm

#endif  // OPENFM_EFFECTS_H_

/*
 * Copyright 2012 Google Inc.
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

#ifdef VERBOSE
#include <iostream>
#endif

#include "synth.h"
#include "sin.h"
#include "fm_op_kernel.h"
#include "fm_core.h"

using namespace std;

struct FmOperatorInfo {
  int in;
  int out;
};

enum FmOperatorFlags {
  OUT_BUS_ONE = 1 << 0,
  OUT_BUS_TWO = 1 << 1,
  OUT_BUS_ADD = 1 << 2,
  IN_BUS_ONE = 1 << 4,
  IN_BUS_TWO = 1 << 5,
  FB_IN = 1 << 6,
  FB_OUT = 1 << 7
};

struct FmAlgorithm {
  int ops[6];
};

const FmAlgorithm algorithms[32] = {
  { { 0xc1, 0x11, 0x11, 0x14, 0x01, 0x14 } }, // 1
  { { 0x01, 0x11, 0x11, 0x14, 0xc1, 0x14 } }, // 2
  { { 0xc1, 0x11, 0x14, 0x01, 0x11, 0x14 } }, // 3
  { { 0x41, 0x11, 0x94, 0x01, 0x11, 0x14 } }, // 4
  { { 0xc1, 0x14, 0x01, 0x14, 0x01, 0x14 } }, // 5
  { { 0x41, 0x94, 0x01, 0x14, 0x01, 0x14 } }, // 6
  { { 0xc1, 0x11, 0x05, 0x14, 0x01, 0x14 } }, // 7
  { { 0x01, 0x11, 0xc5, 0x14, 0x01, 0x14 } }, // 8
  { { 0x01, 0x11, 0x05, 0x14, 0xc1, 0x14 } }, // 9
  { { 0x01, 0x05, 0x14, 0xc1, 0x11, 0x14 } }, // 10
  { { 0xc1, 0x05, 0x14, 0x01, 0x11, 0x14 } }, // 11
  { { 0x01, 0x05, 0x05, 0x14, 0xc1, 0x14 } }, // 12
  { { 0xc1, 0x05, 0x05, 0x14, 0x01, 0x14 } }, // 13
  { { 0xc1, 0x05, 0x11, 0x14, 0x01, 0x14 } }, // 14
  { { 0x01, 0x05, 0x11, 0x14, 0xc1, 0x14 } }, // 15
  { { 0xc1, 0x11, 0x02, 0x25, 0x05, 0x14 } }, // 16
  { { 0x01, 0x11, 0x02, 0x25, 0xc5, 0x14 } }, // 17
  { { 0x01, 0x11, 0x11, 0xc5, 0x05, 0x14 } }, // 18
  { { 0xc1, 0x14, 0x14, 0x01, 0x11, 0x14 } }, // 19
  { { 0x01, 0x05, 0x14, 0xc1, 0x14, 0x14 } }, // 20
  { { 0x01, 0x14, 0x14, 0xc1, 0x14, 0x14 } }, // 21
  { { 0xc1, 0x14, 0x14, 0x14, 0x01, 0x14 } }, // 22
  { { 0xc1, 0x14, 0x14, 0x01, 0x14, 0x04 } }, // 23
  { { 0xc1, 0x14, 0x14, 0x14, 0x04, 0x04 } }, // 24
  { { 0xc1, 0x14, 0x14, 0x04, 0x04, 0x04 } }, // 25
  { { 0xc1, 0x05, 0x14, 0x01, 0x14, 0x04 } }, // 26
  { { 0x01, 0x05, 0x14, 0xc1, 0x14, 0x04 } }, // 27
  { { 0x04, 0xc1, 0x11, 0x14, 0x01, 0x14 } }, // 28
  { { 0xc1, 0x14, 0x01, 0x14, 0x04, 0x04 } }, // 29
  { { 0x04, 0xc1, 0x11, 0x14, 0x04, 0x04 } }, // 30
  { { 0xc1, 0x14, 0x04, 0x04, 0x04, 0x04 } }, // 31
  { { 0xc4, 0x04, 0x04, 0x04, 0x04, 0x04 } }, // 32
};

int n_out(const FmAlgorithm &alg) {
  int count = 0;
  for (int i = 0; i < 6; i++) {
    if ((alg.ops[i] & 7) == OUT_BUS_ADD) count++;
  }
  return count;
}

void FmCore::dump() {
#ifdef VERBOSE
  for (int i = 0; i < 32; i++) {
    cout << (i + 1) << ":";
    const FmAlgorithm &alg = algorithms[i];
    for (int j = 0; j < 6; j++) {
      int flags = alg.ops[j];
      cout << " ";
      if (flags & FB_IN) cout << "[";
      cout << (flags & IN_BUS_ONE ? "1" : flags & IN_BUS_TWO ? "2" : "0") << "->";
      cout << (flags & OUT_BUS_ONE ? "1" : flags & OUT_BUS_TWO ? "2" : "0");
      if (flags & OUT_BUS_ADD) cout << "+";
      //cout << alg.ops[j].in << "->" << alg.ops[j].out;
      if (flags & FB_OUT) cout << "]";
    }
    cout << " " << n_out(alg);
    cout << endl;
  }
#endif
}

// Modified for OpenFM (2026): flags()/isCarrier() accessors and compute_fb_chain for feedback loops spanning 2 or 3 operators.
int FmCore::flags(int algorithm, int op) {
  return algorithms[algorithm & 31].ops[op % 6];
}

bool FmCore::isCarrier(int algorithm, int op) {
  return (algorithms[algorithm & 31].ops[op % 6] & 3) == 0;
}

// A serial chain of `n` operators whose final output feeds back into the
// first one (DX7 algorithms 4 and 6). Always accumulates into `output`.
static void compute_fb_chain(int32_t *output, FmOpParams *params, int n,
                             int32_t *fb_buf, int fb_shift) {
  int32_t gain[3], dgain[3], phase[3], freq[3];
  for (int k = 0; k < n; k++) {
    gain[k] = params[k].gain[0];
    dgain[k] = (params[k].gain[1] - params[k].gain[0] + (N >> 1)) >> LG_N;
    phase[k] = params[k].phase;
    freq[k] = params[k].freq;
  }
  int32_t y0 = fb_buf[0];
  int32_t y = fb_buf[1];
  for (int i = 0; i < N; i++) {
    int32_t s = (y0 + y) >> (fb_shift + 1);
    y0 = y;
    for (int k = 0; k < n; k++) {
      gain[k] += dgain[k];
      s = (int32_t)(((int64_t)Sin::lookup(phase[k] + s) * (int64_t)gain[k]) >> 24);
      phase[k] += freq[k];
    }
    y = s;
    output[i] += y;
  }
  fb_buf[0] = y0;
  fb_buf[1] = y;
}

void FmCore::compute(int32_t *output, FmOpParams *params, int algorithm,
                     int32_t *fb_buf, int feedback_shift) {
  const int kLevelThresh = 1120;
  const FmAlgorithm alg = algorithms[algorithm];
  bool has_contents[3] = { true, false, false };
  int first_op = 0;
  if (feedback_shift < 16 && (algorithm == 3 || algorithm == 5)) {
    first_op = (algorithm == 3) ? 3 : 2;
    compute_fb_chain(output, params, first_op, fb_buf, feedback_shift);
    for (int op = 0; op < first_op; op++) {
      params[op].phase += params[op].freq << LG_N;
    }
  }
  for (int op = first_op; op < 6; op++) {
    int flags = alg.ops[op];
    bool add = (flags & OUT_BUS_ADD) != 0;
    FmOpParams &param = params[op];
    int inbus = (flags >> 4) & 3;
    int outbus = flags & 3;
    int32_t *outptr = (outbus == 0) ? output : buf_[outbus - 1].get();
    int32_t gain1 = param.gain[0];
    int32_t gain2 = param.gain[1];
    if (gain1 >= kLevelThresh || gain2 >= kLevelThresh) {
      if (!has_contents[outbus]) {
        add = false;
      }
      if (inbus == 0 || !has_contents[inbus]) {
        // todo: more than one op in a feedback loop
        if ((flags & 0xc0) == 0xc0 && feedback_shift < 16) {
          // cout << op << " fb " << inbus << outbus << add << endl;
          FmOpKernel::compute_fb(outptr, param.phase, param.freq,
                                 gain1, gain2,
                                 fb_buf, feedback_shift, add);
        } else {
          // cout << op << " pure " << inbus << outbus << add << endl;
          FmOpKernel::compute_pure(outptr, param.phase, param.freq,
                                   gain1, gain2, add);
        }
      } else {
        // cout << op << " normal " << inbus << outbus << " " << param.freq << add << endl;
        FmOpKernel::compute(outptr, buf_[inbus - 1].get(),
                            param.phase, param.freq, gain1, gain2, add);
      }
      has_contents[outbus] = true;
    } else if (!add) {
      has_contents[outbus] = false;
    }
    param.phase += param.freq << LG_N;
  }
}

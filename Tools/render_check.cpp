// Offline sanity check for the engine: renders a chord and prints levels.
//   clang++ -std=c++20 -O2 -IOpenFMKit/Sources/OpenFMEngine -IOpenFMKit/Sources/OpenFMEngine/msfa Tools/render_check.cpp OpenFMKit/Sources/OpenFMEngine/*.cpp OpenFMKit/Sources/OpenFMEngine/msfa/*.cc -o /tmp/render_check
#include <chrono>
#include <cmath>
#include <cstdio>
#include <vector>
#include "Engine.h"

int main() {
  openfm::Engine e;
  e.prepare(48000);
  uint8_t p[156];
  openfm::Engine::initPatch(p);
  for (int alg = 0; alg < 32; alg++) {
    p[134] = alg; p[135] = 7;
    for (int op = 0; op < 6; op++) { p[op*21+16] = 85; p[op*21+7] = 0; p[op*21+3] = 60; }
    e.loadPatch(p);
    for (int n : {48, 55, 60, 64}) e.pushEvent(openfm::Engine::kQueueUI, 0x90, n, 100);
    std::vector<float> l(480), r(480);
    double peak = 0, sum = 0; bool bad = false;
    auto t0 = std::chrono::steady_clock::now();
    for (int b = 0; b < 100; b++) {
      if (b == 60) for (int n : {48, 55, 60, 64}) e.pushEvent(openfm::Engine::kQueueUI, 0x80, n, 0);
      e.render(l.data(), r.data(), 480);
      for (float x : l) { if (!std::isfinite(x)) bad = true; peak = std::fmax(peak, std::fabs(x)); sum += x * x; }
    }
    auto dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    // let it ring out
    for (int b = 0; b < 400; b++) e.render(l.data(), r.data(), 480);
    printf("alg %2d peak %.3f rms %.3f voices-after %d cpu %.1f%%%s\n", alg + 1, peak,
           std::sqrt(sum / 48000.0), e.activeVoices(), dt * 100.0, bad ? " NaN!" : "");
    e.panic();
  }
  // 16-voice load
  for (int n = 40; n < 60; n++) e.pushEvent(openfm::Engine::kQueueUI, 0x90, n, 100);
  std::vector<float> l(480), r(480);
  auto t0 = std::chrono::steady_clock::now();
  for (int b = 0; b < 100; b++) e.render(l.data(), r.data(), 480);
  auto dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  printf("20 notes -> %d voices, %.2f%% of realtime\n", e.activeVoices(), dt * 100.0);
  return 0;
}

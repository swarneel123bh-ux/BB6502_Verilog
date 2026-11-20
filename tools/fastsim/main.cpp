// Paced Verilator runner for the BB6502 system (rtl/tb.v, 1 MHz clock).
// Advances simulated time in half-clock steps and sleeps whenever the
// simulation runs ahead of the wall clock, so 1 s of sim = 1 s of real time.
// Usage: Vtb [-fast] [-seconds N]   (-fast: run flat out; -seconds: stop after N sim seconds)
#include "Vtb.h"
#include "verilated.h"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <thread>

int main(int argc, char **argv) {
  bool pace = true;
  double stop_s = -1.0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-fast")) pace = false;
    else if (!strcmp(argv[i], "-seconds") && i + 1 < argc) stop_s = atof(argv[++i]);
  }

  VerilatedContext *ctx = new VerilatedContext;
  Vtb *top = new Vtb(ctx);

  const uint64_t HALF_PERIOD_PS = 500000;   // 500 ns: the clock toggles every 500 ns (1 MHz)
  const uint64_t STOP_PS = stop_s > 0 ? (uint64_t)(stop_s * 1e12) : UINT64_MAX;
  const int CHECK_EVERY = 256;               // how often to compare with the wall clock

  auto t0 = std::chrono::steady_clock::now();
  uint64_t steps = 0;
  while (!ctx->gotFinish() && ctx->time() < STOP_PS) {
    ctx->timeInc(HALF_PERIOD_PS);
    top->eval();
    if (pace && (++steps % CHECK_EVERY) == 0) {
      uint64_t sim_ns = ctx->time() / 1000;
      auto wall = std::chrono::steady_clock::now() - t0;
      uint64_t wall_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(wall).count();
      if (sim_ns > wall_ns)
        std::this_thread::sleep_for(std::chrono::nanoseconds(sim_ns - wall_ns));
    }
  }
  double wall_s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  fprintf(stderr, "\n[fastsim] sim %.3f s in wall %.3f s (%s)\n", ctx->time() / 1e12, wall_s,
          pace ? "paced" : "flat out");
  top->final();
  delete top;
  delete ctx;
  return 0;
}

module proc.sim.simulation;

import std.typecons : Tuple, tuple;

struct Simulation {
  struct SplitOption {
    ulong rid;
    ulong bid;
    ulong[] splits;
  }

  alias RunnerTime = Tuple!(size_t, "rid", ulong, "time");
  RunnerTime[] startTimePerRunner;
  SplitOption[] fos;

  @property static Simulation def() {
    Simulation sim;
    sim.startTimePerRunner ~= RunnerTime(0UL, 0UL);
    // sim.startTimePerRunner ~= RunnerTime(1UL, 0UL);
    return sim;
  }
}

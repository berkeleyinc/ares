module proc.sim.simulation;

import std.typecons : Tuple, tuple;

struct Simulation {
  struct SplitOption {
    ulong tid;
    ulong bid;
    ulong[] splits;
  }

  alias TokenTime = Tuple!(size_t, "tid", ulong, "time");
  TokenTime[] startTimePerToken;
  SplitOption[] fos;

  @property static Simulation def() {
    Simulation sim;
    sim.startTimePerToken ~= TokenTime(0UL, 0UL);
    // sim.startTimePerToken ~= TokenTime(0UL, 0UL);
    // sim.startTimePerToken ~= TokenTime(1UL, 0UL);
    return sim;
  }

  static Simulation construct(size_t tokenCount, ulong timeBetween) {
    Simulation sim;
    ulong rt = 0;
    foreach (size_t i; 0 .. tokenCount) {
      sim.startTimePerToken ~= [tuple!("tid", "time")(i, rt)];
      rt += timeBetween;
    }
    return sim;
  }
}

module proc.sim.multiple;

import proc.sim.simulator;
import proc.sim.simulation;
import proc.sim.pathFinder;
import proc.businessProcess;
import util;

import std.typecons;
import std.range;
import std.algorithm;

class MultiSimulator {
  // simulates BusinessProcess $p $count times from $startID to $endID, all with random paths
  static double multiSimulate(const BusinessProcess p, ulong count = 500,
      Nullable!ulong startID = Nullable!ulong.init, Nullable!ulong endID = Nullable!ulong.init) {
    auto sor = new Simulator(p);
    return generate!(() => sor.simulate(startID, endID)).takeExactly(count).mean;
  }

  static double multiSimulate(Simulator sor, const BusinessProcess p, ulong count = 500,
      Nullable!ulong startID = Nullable!ulong.init, Nullable!ulong endID = Nullable!ulong.init) {
    return generate!(() => sor.simulate(startID, endID)).takeExactly(count).mean;
  }

  static double allPathSimulate(const BusinessProcess inp) {
    Simulation[] sims;
    return allPathSimulate(inp, sims);
  }

  static double allPathSimulate(Simulator sor, const BusinessProcess inp) {
    Simulation[] sims;
    return allPathSimulate(sor, inp, sims);
  }

  static double allPathSimulate(const BusinessProcess inp, out Simulation[] sims) {
    return allPathSimulate(new Simulator(inp), inp, sims);
  }
  static double allPathSimulate(Simulator sor, const BusinessProcess inp, out Simulation[] sims) {
    return allPathSimulate(sor, inp, Simulation.def, sims);
  }

  static double allPathSimulate(Simulator sor, const BusinessProcess inp, in Simulation defSim) {
    Simulation[] sims;
    return allPathSimulate(sor, inp, defSim, sims);
  }

  // simulates input BP and returns time units for all path simulations
  // sims: those Simulations consist of SplitOptions that choose all avaiable paths
  static double allPathSimulate(Simulator sor, const BusinessProcess inp, in Simulation defSim, out Simulation[] sims) {
    PathFinder pf = new PathFinder(inp);

    ulong[][] paths = pf.findPaths();
    if (paths.empty)
      throw new Exception("PathFinder couldn't find any paths");

    foreach (ref p; paths) {
      import util; 
      Simulation sim = defSim.gdup;
      Simulation.SplitOption[] sos;
      foreach (i, ee; p) {
        if (inp(ee).isGate && inp(ee).succs.length > 1 && inp(ee).asGate.type != Gate.Type.and) {
          foreach (ref rt; sim.startTimePerToken)
            sos ~= Simulation.SplitOption(rt.tid, ee, [p[i + 1]]);
        }
      }
      sim.fos = sos;
      sims ~= sim;
      // writeln("SIM.sos: ", sim.fos);
      // writeln(" -> p: ", p, " <--> ", p.filter!(bo => inp(bo).isGate && inp(bo).succs.length > 1 && inp(bo)
      //     .asGate.type != Gate.Type.and));
    }

    ulong[] times;
    foreach (ref sim; sims) {
      times ~= sor.simulate(sim);
    }
    return times[].mean;
  }

}

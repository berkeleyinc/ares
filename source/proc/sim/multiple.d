module proc.sim.multiple;

import proc.sim.simulator;
import proc.sim.simulation;
import proc.sim.pathFinder;
import proc.process;
import util;

import std.typecons;
import std.range;
import std.algorithm;

class MultiSimulator {
  // simulates Process $p $count times from $startID to $endID, all with random paths
  static double multiSimulate(const Process p, ulong count = 500,
      Nullable!ulong startID = Nullable!ulong.init, Nullable!ulong endID = Nullable!ulong.init) {
    auto sor = new Simulator(p);
    return generate!(() => sor.simulate(startID, endID)).takeExactly(count).mean;
  }

  static double allPathSimulate(const Process inp) {
    Simulation[] sims;
    return allPathSimulate(inp, sims);
  }

  static double allPathSimulate(Simulator sor, const Process inp) {
    Simulation[] sims;
    return allPathSimulate(sor, inp, sims);
  }

  static double allPathSimulate(const Process inp, out Simulation[] sims) {
    return allPathSimulate(new Simulator(inp), inp, sims);
  }
  // simulates input BP and returns time units for all path simulations
  // sims: those Simulations consist of SplitOptions that choose all avaiable paths
  static double allPathSimulate(Simulator sor, const Process inp, out Simulation[] sims) {
    PathFinder pf = new PathFinder(inp);

    ulong[][] paths = pf.findPaths();
    if (paths.empty)
      throw new Exception("PathFinder couldn't find any paths");

    foreach (ref p; paths) {
      Simulation sim = Simulation.def;
      Simulation.SplitOption[] sos;
      foreach (i, bo; p) {
        if (inp(bo).isConn && inp(bo).succs.length > 1 && inp(bo).asConn.type != Connector.Type.and) {
          foreach (ref rt; sim.startTimePerRunner)
            sos ~= Simulation.SplitOption(rt.rid, bo, [p[i + 1]]);
        }
      }
      sim.fos = sos;
      sims ~= sim;
      // writeln("SIM.sos: ", sim.fos);
      // writeln(" -> p: ", p, " <--> ", p.filter!(bo => inp(bo).isConn && inp(bo).succs.length > 1 && inp(bo)
      //     .asConn.type != Connector.Type.and));
    }

    ulong[] times;
    foreach (ref sim; sims) {
      times ~= sor.simulate(sim);
    }
    return times.mean;
  }

}

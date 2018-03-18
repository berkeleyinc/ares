module proc.mod.assignMod;

import proc.mod.modification;
import proc.process;
import proc.sim.simulation;

import std.algorithm.iteration;

class AssignMod : Modification {
  // part will be assigned to each of funcs
  this(ulong partID, ulong[] funcIDs) {
    partID_ = partID;
    funcIDs_ = funcIDs.dup;
  }

  override @property string toString() {
    return "Assign P" ~ partID_.text ~ " to funcs: " ~ funcIDs_.text;
  }

  override void apply(Process proc) {
    proc(partID_).asRes.deps = funcIDs_;
    proc.postProcess();
  }

  static Modification[] create(const Process p, in Simulation defSim) {
    return (new AssignModFactory(p)).create(defSim);
  }

private:
  ulong partID_;
  ulong[] funcIDs_;
}

import proc.sim.multiple;
import proc.sim.simulator;
import std.typecons;
import std.array;
import std.algorithm;
import std.stdio;
import std.range;
import std.conv;

import util : mean;
import opmix.dup;

private class AssignModFactory {
  this(const Process p) {
    proc_ = p;
  }

  Modification[] create(in Simulation defSim) {
    writeln(__FUNCTION__, " (assignMod)");
    Modification[] pms;

    Simulation[] sims;
    Process p = proc_.clone();
    Simulator sor = new Simulator(p);

    ulong[ulong] occByPID;
    double timeTaken;

    sor.fnOnStartFunction = (ulong partID, ulong currTime, ulong dur) {
      // writeln("Start P", partID, ", currTime=", currTime, ", dur=", dur);
      occByPID[partID] += dur;
    };

    foreach (ref pa; proc_.ress)
      occByPID[pa.id] = 0;
    timeTaken = MultiSimulator.allPathSimulate(sor, proc_, defSim, sims);
    // timeTaken = generate!(() { auto sim = defSim.gdup; auto t = sor.simulate(sim); sims ~= sim; return t;  })
    //   .takeExactly(700).mean;
    writeln("time: ", timeTaken, " -- occByPID: ", occByPID, ", ", proc_.ress.length, " ress");

    auto occs = occByPID.byKeyValue().array.sort!"a.value < b.value";
    //auto mn = occs[0]; //occByPID.byKeyValue().minElement!"a.value";
    auto mx = occs[$ - 1]; //occByPID.byKeyValue().maxElement!"a.value";

    for (int i = 0; i < occs.length - 1; i++) {
      auto mn = occs[i];
      auto depsWant = (proc_(mn.key).deps ~ proc_(mx.key).deps).dup.sort.uniq.array;
      ulong[] depsCan;
      // remove all funcs for which we don't have a qualification
      foreach (qid; proc_(mn.key).asRes.quals) {
        if (depsWant.canFind(qid))
          depsCan ~= qid;
      }
      if (depsCan != proc_(mn.key).deps) {
        pms ~= new AssignMod(mn.key, depsCan);
        writeln("maybe ", pms[$ - 1].toString());
      }
    }

    return pms;
  }

private:
  const Process proc_;
}

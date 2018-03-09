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
    return "Assign " ~ partID_.text ~ " to funcs: " ~ funcIDs_.text;
  }

  override void apply(Process proc) {
    proc(partID_).asPart.deps = funcIDs_;
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
      occByPID[partID]++;
    };
    // TODO find runnerCount for current UserCfg
    // Simulation defSim = Simulation.construct(runnerCount, timeBetween);
    // defSim.startTimePerRunner ~= Simulation.RunnerTime(1UL, 0UL);
    // defSim.startTimePerRunner ~= Simulation.RunnerTime(2UL, 0UL);

    // if (timeTaken!= 382764)
    //   return [];

    foreach (ref pa; proc_.parts)
      occByPID[pa.id] = 0;
    timeTaken = MultiSimulator.allPathSimulate(sor, proc_, defSim, sims);
    // timeTaken = generate!(() { auto sim = defSim.gdup; auto t = sor.simulate(sim); sims ~= sim; return t;  })
    //   .takeExactly(700).mean;
    writeln("time: ", timeTaken, " -- occByPID: ", occByPID, ", ", proc_.parts.length, " parts");

    auto occs = occByPID.byKeyValue().array.sort!"a.value < b.value";
    //auto mn = occs[0]; //occByPID.byKeyValue().minElement!"a.value";
    auto mx = occs[$ - 1]; //occByPID.byKeyValue().maxElement!"a.value";

    for (int i = 0; i < min(3, occs.length - 1); i++) {
      auto mn = occs[i];

      pms ~= new AssignMod(mn.key, (proc_(mn.key).deps ~ proc_(mx.key).deps).dup.sort.uniq.array);
      writeln("maybe ", pms[$ - 1].toString());
    }

    // foreach (ref pa; proc_.parts)
    //   occByPID[pa.id] = 0;
    // sor.process = p;
    // //proc(mn.key).deps = proc(mn.key).deps ~ proc(mx.key).deps;
    // p(7).deps ~= 16;
    // p(9).deps ~= 12;
    // p.postProcess();

    // size_t i = 0;
    // timeTaken = generate!(() => sor.simulate(sims[i++])).takeExactly(700).mean;
    // writeln("time: ", timeTaken, " -- occByPID: ", occByPID);
    /*

    foreach (ref pa; proc_.parts)
      occByPID[pa.id] = 0;
    p(7).deps ~= 16;
    p(9).deps ~= 12;
    p.postProcess();
    size_t i = 0;
    timeTaken = generate!(() => sor.simulate(sims[i++])).takeExactly(700).mean;
    writeln("time: ", timeTaken, " -- occByPID: ", occByPID);

    // pms ~= AssignMod(9, p(9).deps);


    foreach (ref pa; proc_.parts)
      occByPID[pa.id] = 0;
    // p(9).deps ~= 16;
    p(9).deps ~= 16;
    p.postProcess();
    i = 0;
    timeTaken = generate!(() { sor.process = p; return sor.simulate(sims[i++]); }).takeExactly(700).mean;
    writeln("time: ", timeTaken, " -- occByPID: ", occByPID);
    */

    return pms;
  }

private:
  const Process proc_;
}

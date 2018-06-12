module proc.mod.assignMod;

import proc.mod.modification;
import proc.businessProcess;
import proc.sim.simulation;

import std.algorithm.iteration;

class AssignMod : Modification {
  // part will be assigned to each of funcs
  this(ulong partID, ulong[] funcIDs) {
    partID_ = partID;
    funcIDs_ = funcIDs.dup;
  }

  override @property string toString() const {
    return "Assign R" ~ partID_.text ~ " to funcs: " ~ funcIDs_.text;
  }

  override void apply(BusinessProcess proc) {
    proc(partID_).asRes.deps = funcIDs_;
    proc.postProcess();
  }

  static Modification[] create(const BusinessProcess p, in Simulation defSim) {
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
  this(const BusinessProcess p) {
    proc_ = p;
  }

  Modification[] create(in Simulation defSim) {
    writeln(__FUNCTION__, " (assignMod)");
    Modification[] pms;

    Simulation[] sims;
    BusinessProcess p = proc_.clone();
    Simulator sor = new Simulator(p);

    ulong[ulong] occByRID;
    double timeTaken;

    sor.fnOnStartFunction = (ulong resourceID, ulong currTime, ulong dur) {
      // writeln("Start P", partID, ", currTime=", currTime, ", dur=", dur);
      occByRID[resourceID] += dur;
    };

    foreach (ref pa; proc_.ress)
      occByRID[pa.id] = 0;
    timeTaken = MultiSimulator.allPathSimulate(sor, proc_, defSim, sims);
    // timeTaken = generate!(() { auto sim = defSim.gdup; auto t = sor.simulate(sim); sims ~= sim; return t;  })
    //   .takeExactly(700).mean;
    writeln("time: ", timeTaken, " -- occByRID: ", occByRID, ", ", proc_.ress.length, " ress");

    auto occs = occByRID.byKeyValue().array.sort!"a.value < b.value";
    //auto mn = occs[0]; //occByRID.byKeyValue().minElement!"a.value";
    auto occMax = occs[$ - 1]; //occByRID.byKeyValue().maxElement!"a.value";

    for (int i = 0; i < occs.length - 1; i++) {
      auto mn = occs[i];
      auto depsWant = (proc_(mn.key).deps ~ proc_(occMax.key).deps).dup.sort.uniq.array;
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

    if (proc_(occMax.key).deps.length > 1) {
      ulong[] must;
      foreach (depID; proc_(occMax.key).deps) {
        bool found = false;
        foreach (ref res; proc_.ress)
          if (res.id != occMax.key && proc_(res.id).deps.canFind(depID))
            found = true;
        if (!found)
          must ~= depID;
      }
      //assert(!must.empty); // TODO must could be empty actually

      if (!must.empty && must != proc_(occMax.key).deps)
        pms ~= new AssignMod(occMax.key, must);
    }

    return pms;
  }

  private:
  const BusinessProcess proc_;
}

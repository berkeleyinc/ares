module proc.mod.businessProcessModifier;

import proc.businessProcess;

import std.algorithm;
import std.stdio : writeln;
import std.array;
import std.typecons;
import std.math : abs, round;
import std.range : iota, generate, take, takeExactly, repeat, empty;
import std.conv;
import std.datetime;
import std.datetime.stopwatch : AutoStart, StopWatch;

import proc.sim.simulator;
import proc.sim.simulation;
import proc.sim.multiple;

import proc.mod.modification;
import proc.mod.moveMod;
import proc.mod.parallelizeMod;
import proc.mod.assignMod;

import util;

class BusinessProcessModifier {
  this(const BusinessProcess p, const Simulation defSim) {
    proc_ = p;
    defSim_ = defSim;
  }

  BusinessProcess[] modify(out string resultStr) {

    string[] result;
    auto sw = StopWatch(AutoStart.yes);
    scope (exit) {
      result ~= "Runtime: " ~ text(sw.peek());
      resultStr = result.joiner("\n").text;
    }

    ModsOption[] mos;

    // origProcTime_ = MultiSimulator.allPathSimulate(proc_);
    // auto mods = MoveMod.create(proc_);
    // if (mods.empty) {
    //   result ~= "No move-optimizations found";
    //   return [];
    // }
    // auto nt = MultiSimulator.allPathSimulate(proc_);
    // BusinessProcess np = proc_.clone();
    // mos ~= ModsOption(np, nt, [mods[0]]);

    // if (!findOptimalModifications(mos, &ParallelizeMod.create)) {
    if (!findOptimalModifications(mos, &ParallelizeMod.create, &MoveMod.create, &AssignMod.create)) {
      result ~= "No optimizations found";
      return [];
    }

    // savedTime += time;
    // allMods ~= mods;
    // mods.each!(m => m.apply(proc_));

    // time = findOptimalModifications(mods, &ParallelizeMod.create);
    // if (time > 0) {
    //   savedTime += time;
    //   allMods ~= mods;
    //   mods.each!(m => m.apply(proc_));
    // }
    // }

    // mods.each!(m => m.apply(proc_));
    // result ~= donePts.length.text ~ " final processes found.";
    // result ~= "Runtimes: " ~ donePts.map!(a => a.runtime).text;

    result ~= "Best restruct. BP is " ~ (origProcTime_ - mos[0].runtime)
      .text ~ " units faster (" ~ origProcTime_.text ~ " -> " ~ mos[0].runtime.text ~ ")";
    result ~= mos[0].mods.map!(pm => "\t" ~ pm.toString).joiner("\n").text;
    result ~= "Times for each restruct. BP: " ~ mos.map!(mo => mo.runtime).text;
    // result ~= "origProcTime_=" ~ origProcTime_.text ~ ", savedTime=" ~ savedTime.text;
    return mos.map!"a.proc".array;
  }

private:
  const Simulation defSim_;

  Rebindable!(const BusinessProcess) proc_;
  double origProcTime_ = -1; // BP Simulation.def time from input process

  struct ModsOption {
    BusinessProcess proc;
    double runtime;
    Modification[] mods;
    int sameTimeCount;
  }

  // returns saved time units
  bool findOptimalModifications(FactoryFuncs...)(out ModsOption[] mos, auto ref FactoryFuncs ffuncs) {
    writeln(__FUNCTION__);
    Simulation[] sims;
    Simulator sor = new Simulator(null);
    // double origTime = MultiSimulator.allPathSimulate(proc_, sims);

    // grab multiple Runners amount from UserConfig
    const Simulation defSim = defSim_;
    sor.process = proc_;
    // double origTime = generate!(() {
    //   auto sim = defSim.gdup;
    //   auto t = sor.simulate(sim);
    //   sims ~= sim;
    //   return t;
    // }).takeExactly(250).mean;
    double origTime = MultiSimulator.allPathSimulate(sor, proc_, defSim, sims);

    if (origProcTime_ < 0)
      origProcTime_ = origTime;

    auto watch = StopWatch(AutoStart.yes);

    ModsOption[] sourceBPMods = [ModsOption(proc_.clone(), origTime, [], 0)], donePts = [];
    while (!sourceBPMods.empty) {
      auto sourceBPMod = sourceBPMods[0];
      sourceBPMods = sourceBPMods.remove(0);
      // BusinessProcess paired with applied Modification and resulting runtime
      alias PTM = Tuple!(BusinessProcess, "proc", double, "runtime", Modification, "mod", int, "sameTimeDiff");
      PTM[] ptms;
      Modification[] pms;

      foreach (createFunc; ffuncs)
        pms ~= createFunc(sourceBPMod.proc, defSim);
      // bool allAssigns = true;
      // foreach (ref pm; pms)
      //   if (pm !is AssignMod) {
      //     allAssigns = false;
      //     break;
      //   }
      // if (allAssigns && !pms.empty) {
      //   origTime = MultiSimulator.allPathSimulate(sor, proc_, defSim, sims);
      // }

      // pms ~= factory.create();
      // pms ~= MoveMod.create(pt.proc);
      // pms ~= ParallelizeMod.create(pt.proc);
      // result ~= pms.length.text ~ " pms found";
      // writeln("pms: ", pms);
      if (pms.empty) {
        if (!sourceBPMod.mods.empty)
          donePts ~= sourceBPMod;
        // sourceBPMods = sourceBPMods.remove(0);
        continue;
      }


      checkNewModsLoop: foreach (m; pms) {
        foreach (mod; sourceBPMod.mods)
          if (m.toHash == mod.toHash)
            continue checkNewModsLoop;

        BusinessProcess p = sourceBPMod.proc.clone();
        // writeln("Apply " ~ m.toString);
        m.apply(p);
        sor.process = p;
        //double origTime = MultiSimulator.allPathSimulate(sor, proc_, defSim, sims);
        // double time = MultiSimulator.multiSimulate(sor, p, 500);
        double time = MultiSimulator.allPathSimulate(sor, p, defSim);
        // ulong[] times;
        // foreach (i, ref sim; sims)
        //   times ~= sor.simulate(sim);
        // double time = times[].mean;
        // writeln("DONE, ", time);
        //if (sourceBPMod.runtime == 0 || time <= sourceBPMod.runtime)
        {

          // if (time == sourceBPMod.runtime && sourceBPMod.sameTimeCount >= 5) {
          // } else
          {
            // Simulation[] newSims;
            // MultiSimulator.allPathSimulate(sor, p, defSim, newSims);
            if (time == sourceBPMod.runtime)
              ptms ~= PTM(p, time, m, 1); //, newSims);
            else
              ptms ~= PTM(p, time, m, -sourceBPMod.sameTimeCount); //, newSims);
          }
        }
      }
      if (ptms.empty) {
        if (!sourceBPMod.mods.empty)
          donePts ~= sourceBPMod;
        // sourceBPMods = sourceBPMods.remove(0);
        continue;
      }
      // sourceBPMods = sourceBPMods.remove(0);
      auto parr = ptms.map!(a => ModsOption(a.proc, a.runtime, sourceBPMod.mods ~ [a.mod],
          sourceBPMod.sameTimeCount + a.sameTimeDiff)).array;
      // auto parr = ptms.sort!"a.runtime < b.runtime".uniq!"a.runtime == b.runtime".map!(a => ModsOption(a.proc, a.runtime, pt.mods ~ [a.mod])).array;
      assert(!parr.empty);
      // if (sourceBPMods.length + donePts.length >= 2)
      //   parr.length = min(2, parr.length);
      // if (sourceBPMods.length + donePts.length >= 5)
      //   parr.length = 1;
      // if (parr.length > 2)
      //   parr.length = 2;
      sourceBPMods ~= parr;
      auto now = watch.peek();
      sourceBPMods = sourceBPMods.sort!"a.runtime < b.runtime".take(now > msecs(2500)
          ? (now > seconds(5) ? (now > seconds(10) ? 1 : 2) : 5) : 100).array;
      // sourceBPMods = sourceBPMods.sort!"a.runtime < b.runtime".uniq!"a.runtime == b.runtime".take(5).array;
    }

    if (donePts.empty)
      return false;

    writeln("BP origTime: ", origTime);
    writeln("Found ", donePts.length.text, " new BPs, runtimes: ", donePts.map!(a => a.runtime));
    // mos = donePts.sort!("a.runtime < b.runtime").release;
    // mos = donePts.sort!("a.runtime < b.runtime").uniq!((a, b) => a.proc.hasSameStructure(b.proc)).array;
    // mos = donePts.sort!("a.runtime < b.runtime").array;
    mos = donePts.sort!("a.runtime < b.runtime")
      .uniq!"a.runtime == b.runtime"
      .array;
    //mos = donePts.sort!("a.runtime < b.runtime").uniq!"a.runtime == b.runtime".array;
    return true;
    // donePts = donePts.sort!"a.runtime < b.runtime".uniq!"a.runtime == b.runtime".array;
    // writeln("Found ", donePts.length.text, " BPs, runtimes: ", donePts.map!(a => a.runtime));
    // auto ptmm = donePts.minElement!"a.runtime < b.runtime";
    // mods ~= ptmm.mods;
    // if (ptmm.mods.empty)
    //   return false;

    // return origTime - ptmm.runtime;
  }
}

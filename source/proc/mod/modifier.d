module proc.mod.modifier;

import proc.process;

import std.algorithm;
import std.stdio : writeln, empty;
import std.array;
import std.typecons;
import std.math : abs, round;
import std.range : iota, generate, take, takeExactly, repeat;
import std.conv;
import std.datetime;
import std.datetime.stopwatch : AutoStart, StopWatch;

import proc.sim.simulator;
import proc.sim.simulation;
import proc.sim.multiple;

import proc.mod.modification;
import proc.mod.embedMod;
import proc.mod.parallelizeMod;

import util;

class Modifier {
  this(const Process p) {
    proc_ = p;
  }

  Process[] modify(out string resultStr) {

    string[] result;
    auto sw = StopWatch(AutoStart.yes);
    scope (exit) {
      result ~= "Runtime: " ~ text(sw.peek());
      resultStr = result.joiner("\n").text;
    }

    ModsOption[] mos;

    // origProcTime_ = MultiSimulator.allPathSimulate(proc_);
    // auto mods = EmbedMod.create(proc_);
    // if (mods.empty) {
    //   result ~= "No embed-optimizations found";
    //   return [];
    // }
    // auto nt = MultiSimulator.allPathSimulate(proc_);
    // Process np = proc_.clone();
    // mos ~= ModsOption(np, nt, [mods[0]]);

    if (!findOptimalModifications(mos, &ParallelizeMod.create, &EmbedMod.create)) {
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
  Rebindable!(const Process) proc_;
  double origProcTime_ = -1; // BP Simulation.def time from input process

  alias ModsOption = Tuple!(Process, "proc", double, "runtime", Modification[], "mods");
  // returns saved time units
  bool findOptimalModifications(FactoryFuncs...)(out ModsOption[] mos, auto ref FactoryFuncs ffuncs) {
    Simulation[] sims;
    double origTime = MultiSimulator.allPathSimulate(proc_, sims);

    if (origProcTime_ < 0)
      origProcTime_ = origTime;

    Simulator sor = new Simulator(null);

    ModsOption[] pts = [ModsOption(proc_.clone(), origTime, [])], donePts = [];
    do {
      foreach (pidx, pt; pts) {
        alias PTM = Tuple!(Process, "proc", double, "runtime", Modification, "mod");
        PTM[] ptms;
        Modification[] pms;

        foreach (createFunc; ffuncs)
          pms ~= createFunc(pt.proc);
        // pms ~= factory.create();
        // pms ~= EmbedMod.create(pt.proc);
        // pms ~= ParallelizeMod.create(pt.proc);
        // result ~= pms.length.text ~ " pms found";
        if (pms.empty) {
          if (!pt.mods.empty)
            donePts ~= pt;
          pts = pts.remove(pidx);
          break;
        }

        foreach (m; pms) {
          Process p = pt.proc.clone();
          // writeln("Apply " ~ m.toString);
          m.apply(p);
          sor.process = p;
          // double time = MultiSimulator.allPathSimulate(sor, proc_);
          ulong[] times;
          foreach (i, sim; sims)
            times ~= sor.simulate(sim);
          double time = times[].mean;
          // writeln("DONE");
          if (pt.runtime == 0 || time < pt.runtime)
            ptms ~= PTM(p, time, m);
        }
        if (ptms.empty) {
          if (!pt.mods.empty)
            donePts ~= pt;
          pts = pts.remove(pidx);
          break;
        }
        pts = pts.remove(pidx);
        auto parr = ptms.map!(a => ModsOption(a.proc, a.runtime, pt.mods ~ [a.mod])).array;
        // auto parr = ptms.sort!"a.runtime < b.runtime".uniq!"a.runtime == b.runtime".map!(a => ModsOption(a.proc, a.runtime, pt.mods ~ [a.mod])).array;
        assert(!parr.empty);
        // if (pts.length + donePts.length >= 2)
        //   parr.length = min(2, parr.length);
        // if (pts.length + donePts.length >= 5)
        //   parr.length = 1;
        // if (parr.length > 2)
        //   parr.length = 2;
        pts ~= parr;
        pts = pts.sort!"a.runtime < b.runtime".uniq!"a.runtime == b.runtime".take(5).array;
        break;
      }
    }
    while (!pts.empty);

    if (donePts.empty)
      return false;

    writeln("Found ", donePts.length.text, " BPs, runtimes: ", donePts.map!(a => a.runtime));
    // mos = donePts.sort!("a.runtime < b.runtime").release;
    // mos = donePts.sort!("a.runtime < b.runtime").uniq!((a, b) => a.proc.hasSameStructure(b.proc)).array;
    mos = donePts.sort!("a.runtime < b.runtime").uniq!"a.runtime == b.runtime".array;
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

module proc.sim.simulator;

import proc.sim.simulation;
import proc.sim.runner;
import proc.process;

import std.algorithm;
import std.stdio : writeln, empty;
import std.conv : text;
import std.random;
import std.array;
import std.typecons;
import std.exception;
import std.range;

import config;
import util;

class Simulator {
  this(const Process proc) {
    this.proc_ = proc;
    rndGen = Random(unpredictableSeed);
  }

  @property void process(const Process p) {
    proc_ = p;
  }

  ulong simulate(Nullable!ulong startID = Nullable!ulong.init, Nullable!ulong endID = Nullable!ulong.init) {
    auto sim = Simulation.def;
    return simulate(sim, startID, endID);
  }

  ulong simulate(ref Simulation sim, Nullable!ulong startID = Nullable!ulong.init,
      Nullable!ulong endID = Nullable!ulong.init) {
    int maxTime = 0;
    currentTime_ = 0;
    runners_ = [];
    queue_.clear;
    psim_ = &sim;
    fillSOs_ = sim.fos.empty;
    foundSOIdcs_ = [];

    const BO startBO = proc_.bos[startID.isNull ? proc_.getStartId() : startID];
    // writeln("StartObject " ~ startBO.name);

    size_t[] runnerIdxStarted;
    bool allRunnersStarted;
    do {
      allRunnersStarted = runnerIdxStarted.length == sim.startTimePerRunner.length;
      if (all!(r => r.currState == Runner.State.wait || r.currState == Runner.State.join)(runners_)) {
        if (!runners_.empty) {
          print("TIME STEP: now=" ~ text(currentTime_));

          ulong incStep = 1;
          if (allRunnersStarted) { // TODO this should also work when not all runners are started

            ulong minContinueDiff = 0;
            foreach (r; runners_) {
              // writeln("r.cont=",r.continueTime);
              if (r.continueTime != 0 && r.continueTime < minContinueDiff || minContinueDiff == 0)
                minContinueDiff = r.continueTime;
            }

            if (minContinueDiff > 0) {
              assert(minContinueDiff >= currentTime_);
              minContinueDiff -= currentTime_;
            }

            incStep = max(1, minContinueDiff);
            // if (incStep > 1)
            // writeln("minContinueDiff=", minContinueDiff);
            // incStep = 1;

            foreach (r; runners_) {
              r.incTime(incStep);
              print(" " ~ r.str);
            }
            if (runners_.length == 1) {
              print(text(queue_));
            }
          }

          if (fnOnIncTime)
            fnOnIncTime();
          currentTime_ += incStep;
        }
        for (int i = 0; i < sim.startTimePerRunner.length; i++) {
          if (currentTime_ >= sim.startTimePerRunner[i].time && !runnerIdxStarted.canFind(i)) {
            runners_ ~= new Runner(&print, sim.startTimePerRunner[i].rid, proc_, queue_, startBO.id, endID);
            runnerIdxStarted ~= i;
            // sim.startTimePerRunner = sim.startTimePerRunner.remove(i);
            // i--;
          }
        }
      }

      for (int i = 0; i < runners_.length; i++) {
        auto r = runners_[i];
        final switch (r.poll(currentTime_)) {
        case Runner.State.end:
          onRunnerEnd(i);
          break;
        case Runner.State.wait:
          break;
        case Runner.State.split:
          onRunnerSplit(i);
          break;
        case Runner.State.join:
          onRunnerJoin(i);
          break;
        case Runner.State.next:
        case Runner.State.none:
          assert(0, "State.none/next shouldn't appear here");
        }
      }

      if (++maxTime > 10000) //  return currentTime_;
        throw new Exception("Error-Simulator: break condition not met");
    }
    while (!runners_.empty || !allRunnersStarted);
    // any!"a.currState != 0"(runners_)

    // foreach (rid; runnerResults_.keys.sort())
    //   print(runnerResults_[rid] ~ " finished.");
    print("DONE, totalTime: " ~ text(currentTime_));
    return currentTime_;
  }

  void delegate(ulong currTime, ulong cID, ulong lastID) fnOnRunnerJoin;
  void delegate(ulong currTime, ulong cID, ulong firstID) fnOnRunnerSplit;
  void delegate() fnOnIncTime;

private:
  Rebindable!(const Process) proc_;
  Runner[] runners_;
  Runner.Queue queue_;
  Simulation* psim_;

  ulong currentTime_;

  // current simulation splitOptions need to be filled not loaded
  bool fillSOs_;
  // Indices of SplitOptions that we already took
  ptrdiff_t[] foundSOIdcs_;

  void print(string msg) {
    // writeln(msg);
  }

  // string[size_t] runnerResults_;

  void onRunnerSplit(ref int runnerElemId) {
    auto r = runners_[runnerElemId];
    auto type = r.currBO.asConn.type;
    immutable bool isAnd = type == Connector.Type.and;
    immutable bool isXor = type == Connector.Type.xor;
    immutable bool isOr = type == Connector.Type.or;

    Rebindable!(const ulong[]) splits;
    if (isAnd)
      splits = r.currBO.succs;
    else {

      if (!fillSOs_) {
        ptrdiff_t foundIdx = -1; // = psim_.fos.countUntil!((fp, r) => r.id == fp.rid && r.currBO.id == fp.bid)(r);
        foreach (i, ref sp; psim_.fos) {
          if (r.id == sp.rid && r.currBO.id == sp.bid && !foundSOIdcs_.canFind(i)) {
            foundIdx = i;
            break;
          }
        }
        // auto savedSplitsForCurrentElem = find!(fp => r.id == fp.rid && r.currBO.id == fp.bid)(psim_.fos);
        if (foundIdx >= 0) {
          // writeln("SOs: ", psim_.fos);
          // prevent usage of this SplitOption from future use during this Simulation
          foundSOIdcs_ ~= foundIdx;
          // assert(savedSplitsForCurrentElem[0] == psim_.fos[idx]);
          // due to the modification "parallelising", some splits from the original Simulation might not point to a successive BO
          // because they are behind connector(s)
          // here we identify the non existant splits and find out their new root BO_ID
          auto fp = psim_.fos[foundIdx];
          ulong[] nonExistantPaths, existantPaths;
          foreach (fid; fp.splits) {
            immutable bool exists = any!(a => a == fid)(r.currBO.succs);
            if (!exists)
              nonExistantPaths ~= fid;
            else
              existantPaths ~= fid;
          }
          nepLoop: for (int i = 0; i < nonExistantPaths.length; i++) {
            foreach (s; r.currBO.succs) {
              immutable bool exists = any!(ss => ss == nonExistantPaths[i])(proc_.listAllObjsAfter(proc_.bos[s],
                  typeid(BO)));
               // if (!exists)
               //   writeln(r.str ~ " ==> nep_i=", nonExistantPaths[i], ", listAllObjsAfter(", proc_(s)
               //       .name, ")=", proc_.listAllObjsAfter(proc_(s), typeid(BO)));
              if (exists) {
                existantPaths ~= s;
                nonExistantPaths = nonExistantPaths.remove(i--);
                if (nonExistantPaths.empty)
                  break nepLoop;
              }
            }
          }
          // TODO nonexistant path wenn ares2.bin vor ares.bin geladen wiurde
          if (!nonExistantPaths.empty) {
            // import graphviz.dotGenerator;
            // generateDot(proc_);
            throw new Exception(r.str ~ " ==> nonExistantPaths=" ~ text(nonExistantPaths) ~ "\nProbably wrong loading order of BPs");
          }
          // assert(nonExistantPaths.empty, r.str ~ " ==> nonExistantPaths=" ~ text(nonExistantPaths));
          splits = existantPaths;
        }
      }

      if (splits.empty) {
        ulong[][] pidcs;
        auto idcs = iota(0, r.currBO.succs.length).array;
        foreach (i; isXor ? [0UL] : idcs[0 .. $])
          pidcs ~= comb(idcs, i + 1).array.dup;
        auto perms = pidcs.map!(a => a.map!(i => r.currBO.succs[i]).array).array;

        double[] probs;
        bool connProbsSet = r.currBO.asConn.probs.any!(p => p.prob > 0);
        for (size_t i = 0; i < perms.length; i++) {
          auto perm = perms[i];
          double total = cast(double) perm.fold!(delegate(t, boId) {
            if (r.currBO.asConn.probs.canFind!(prob => prob.boId == boId))
              return t + r.currBO.asConn.probs.find!(prob => prob.boId == boId)[0].prob;
            else
              return t + (connProbsSet ? 0.0 : 1.0);
          })(0.0);
          probs ~= [total / cast(double) perm.length];
          // writeln("perm=", perm, ", total=", total);
        }

        // writeln("succs: ", r.currBO.succs);
        // writeln("perms: ", perms);
        // writeln("probs: ", probs);
        assert(!perms.empty);

        splits = perms[dice(probs)].array.dup;

        // splits = array(randomSample(r.currBO.succs, isXor ? 1 : uniform!"[]"(1, r.currBO.succs.length)));
        print(r.str ~ ", Chosen splits: " ~ text(splits));
        psim_.fos ~= [Simulation.SplitOption(r.id, r.currBO.id, splits.dup)];
      }
    }

    auto addRunner = delegate Runner(ulong bid) {
      runners_ ~= new Runner(r, bid);
      auto newRunner = runners_[$ - 1];
      if (!r.path.empty) {
        newRunner.pathStart ~= r.path[0];
      }
      newRunner.path = [[]];
      if (r.path.length > 1)
        newRunner.path ~= r.path[1 .. $];
      return newRunner;
    };

    foreach (bid; splits) {
      auto newRunner = addRunner(bid);
      if (fnOnRunnerSplit)
        fnOnRunnerSplit(r.time.func + r.time.queue, r.currBO.id, bid);
      if (isOr) {
        newRunner.branchData ~= Runner.BranchData(splits.length);
      }
    }

    // succLoop: foreach (su; r.currBO.succs) {
    //   foreach (sp; splits)
    //     if (sp == su)
    //       continue succLoop;
    //   auto newRunner = addRunner(su);
    // }

    runners_ = runners_.remove(runnerElemId--);
  }

  void onRunnerJoin(ref int runnerElemId) {
    auto r = runners_[runnerElemId];
    immutable bool isOr = r.currBO.asConn.type == Connector.Type.or;
    immutable bool isXor = r.currBO.asConn.type == Connector.Type.xor;
    immutable bool isAnd = (cast(Connector) r.currBO).type == Connector.Type.and;
    immutable auto runnersAtThisPos = runners_.fold!((a, b) => r.id == b.id && b.currBO.id == r.currBO.id ? a + 1 : a)(
        0);

    size_t desiredRunnersCount;
    if (isAnd)
      desiredRunnersCount = r.currBO.deps.length;
    else if (isXor)
      desiredRunnersCount = 1;
    else { // isOr
      assert(!r.branchData.empty, r.str ~ "'s branchData is empty");
      desiredRunnersCount = r.branchData[$ - 1].concurrentCount;
    }

    if (runnersAtThisPos == desiredRunnersCount) {
      // print(r.str ~ ": All of the " ~ text(desiredRunnersCount) ~ " branches joined");
      ulong mtime = 0;
      Runner mr = null;
      ulong[][] paths;
      for (int i = 0; i < runners_.length; i++) {
        auto ri = runners_[i];
        if (ri.id != r.id)
          continue;
        if (ri.currBO.id == r.currBO.id) {
          if (fnOnRunnerJoin)
            fnOnRunnerJoin(ri.time.func + ri.time.queue, r.currBO.id, ri.lastBOID);
          if (ri.time.func >= mtime) {
            mr = ri;
            mtime = ri.time.func;
          }
          paths ~= ri.path.dup;
          // result ~= rs[i].str ~ " joined\n";
          runners_ = runners_.remove(i--);
          runnerElemId--;
        }
      }

      // if (!isAnd) {
      //   // writeln("kick concurrentCounts=", mr.concurrentCounts[$ - 1]);
      //   mr.concurrentCounts = mr.concurrentCounts[0 .. $ - 1];
      // }
      if (isOr) {
        mr.branchData = mr.branchData[0 .. $ - 1];
      }

      runners_ ~= new Runner(mr, r.currBO.id);
      auto newRunner = runners_[$ - 1];
      newRunner.step();

      if (!newRunner.pathStart.empty) {
        newRunner.path[0] = newRunner.pathStart[$ - 1] ~ newRunner.path[0]; // XXX
        newRunner.pathStart = newRunner.pathStart[0 .. $ - 1];
      }
      foreach (p; mr.path)
        paths = remove!(a => a == p)(paths);
      newRunner.path ~= paths.dup;
    } else {
      // print(r.str ~ ": runnersAtThisPos="~text(runnersAtThisPos)~", desiredRunnersCount="~text(desiredRunnersCount));
    }
  }

  void onRunnerEnd(ref int runnerElemId) {
    // writeln("RUNNER END !!! TIME=", r.time, "\n\n");
    print(runners_[runnerElemId].str ~ " finished.");
    // runnerResults_[runners_[runnerElemId].id] = runners_[runnerElemId].str;
    runners_ = runners_.remove(runnerElemId--);
  }
}

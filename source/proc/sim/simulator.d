module proc.sim.simulator;

import proc.sim.simulation;
import proc.sim.token;
import proc.businessProcess;

import std.algorithm;
import std.stdio : writeln;
import std.conv : text;
import std.random;
import std.array;
import std.typecons;
import std.exception;
import std.range;

import config;
import util;

class Simulator {
  this(const BusinessProcess proc) {
    this.proc_ = proc;
    rndGen = Random(unpredictableSeed);
  }

  @property void process(const BusinessProcess p) {
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
    tokens_ = [];
    queue_.clear;
    psim_ = &sim;
    fillSOs_ = sim.fos.empty;
    foundSOIdcs_ = [];

    const EE startEE = proc_.epcElements[startID.isNull ? proc_.getStartId() : startID];
    // writeln("StartObject " ~ startEE.name);

    size_t[] tokenIdxStarted;
    bool allTokensStarted;
    do {
      allTokensStarted = tokenIdxStarted.length == sim.startTimePerToken.length;
      if (tokens_.all!(r => any!(a => a == r.currState)([Token.State.waitInFunc, Token.State.waitInQueue, Token.State.join]))) {
        if (!tokens_.empty) {
          print("TIME STEP: now=" ~ text(currentTime_));

          ulong incStep = 1;
          if (allTokensStarted) { // TODO this should also work when not all tokens are started

            ulong minContinueDiff = 0;
            foreach (r; tokens_) {
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

            foreach (r; tokens_) {
              r.incTime(incStep);
              print(" " ~ r.str);
            }
            if (tokens_.length == 1) {
              print(text(queue_));
            }
          }

          if (fnOnIncTime)
            fnOnIncTime();
          currentTime_ += incStep;
        }
        for (int i = 0; i < sim.startTimePerToken.length; i++) {
          if (currentTime_ >= sim.startTimePerToken[i].time && !tokenIdxStarted.canFind(i)) {
            tokens_ ~= new Token(&print, fnOnStartFunction, sim.startTimePerToken[i].tid, proc_, queue_, startEE.id, endID);
            tokenIdxStarted ~= i;
            // sim.startTimePerToken = sim.startTimePerToken.remove(i);
            // i--;
          }
        }
      }

      for (int i = 0; i < tokens_.length; i++) {
        auto r = tokens_[i];
        final switch (r.poll(currentTime_)) {
        case Token.State.end:
          onTokenEnd(i);
          break;
        case Token.State.waitInFunc:
          break;
        case Token.State.waitInQueue:
          break;
        case Token.State.split:
          onTokenSplit(i);
          break;
        case Token.State.join:
          onTokenJoin(i);
          break;
        case Token.State.none:
          assert(0, "State.none/next shouldn't appear here");
        }
      }

      if (++maxTime > 10000) {//  return currentTime_;
        // import std.file;
        // import graphviz.dotGenerator;

        // string dot = generateDot(proc_);
        // write("/tmp/graph_break.dot", dot);

        throw new Exception("Error-Simulator: break condition not met");
      }
    }
    while (!tokens_.empty || !allTokensStarted);
    // any!"a.currState != 0"(tokens_)

    // foreach (rid; tokenResults_.keys.sort())
    //   print(tokenResults_[rid] ~ " finished.");
    print("DONE, totalTime: " ~ text(currentTime_));
    return currentTime_;
  }

  void delegate(ulong currTime, ulong cID, ulong lastID) fnOnTokenJoin;
  void delegate(ulong currTime, ulong cID, ulong firstID) fnOnTokenSplit;
  void delegate() fnOnIncTime;
  void delegate(ulong agentID, ulong currTime, ulong duration) fnOnStartFunction;

private:
  Rebindable!(const BusinessProcess) proc_;
  Token[] tokens_;
  Token.Queue queue_;
  Simulation* psim_;

  ulong currentTime_;

  // current simulation splitOptions need to be filled not loaded
  bool fillSOs_;
  // Indices of SplitOptions that we already took
  ptrdiff_t[] foundSOIdcs_;

  void print(string msg) {
    // writeln(msg);
  }

  // string[size_t] tokenResults_;

  void onTokenSplit(ref int tokenElemId) {
    auto r = tokens_[tokenElemId];
    auto type = r.currEE.asGate.type;
    immutable bool isAnd = type == Gate.Type.and;
    immutable bool isXor = type == Gate.Type.xor;
    immutable bool isOr = type == Gate.Type.or;

    Rebindable!(const ulong[]) splits;
    if (isAnd)
      splits = r.currEE.succs;
    else {
      if (!fillSOs_) {
        ptrdiff_t foundIdx = -1; // = psim_.fos.countUntil!((fp, r) => r.id == fp.rid && r.currEE.id == fp.bid)(r);
        foreach (i, ref sp; psim_.fos) {
          if (r.id == sp.tid && r.currEE.id == sp.bid && !foundSOIdcs_.canFind(i)) {
            foundIdx = i;
            break;
          }
        }
        // auto savedSplitsForCurrentElem = find!(fp => r.id == fp.rid && r.currEE.id == fp.bid)(psim_.fos);
        if (foundIdx >= 0) {
          // writeln("SOs: ", psim_.fos);
          // prevent usage of this SplitOption from future use during this Simulation
          foundSOIdcs_ ~= foundIdx;
          // assert(savedSplitsForCurrentElem[0] == psim_.fos[idx]);
          // due to the modification "parallelising", some splits from the original Simulation might not point to a successive EE
          // because they are behind gate(s)
          // here we identify the non existant splits and find out their new root EE_ID
          auto fp = psim_.fos[foundIdx];
          ulong[] nonExistantPaths, existantPaths;
          foreach (fid; fp.splits) {
            immutable bool exists = any!(a => a == fid)(r.currEE.succs);
            if (!exists)
              nonExistantPaths ~= fid;
            else
              existantPaths ~= fid;
          }
          nepLoop: for (int i = 0; i < nonExistantPaths.length; i++) {
            foreach (s; r.currEE.succs) {
              immutable bool exists = any!(ss => ss == nonExistantPaths[i])(proc_.listAllObjsAfter(proc_.epcElements[s],
                  typeid(EE)));
               // if (!exists)
               //   writeln(r.str ~ " ==> nep_i=", nonExistantPaths[i], ", listAllObjsAfter(", proc_(s)
               //       .name, ")=", proc_.listAllObjsAfter(proc_(s), typeid(EE)));
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
        auto idcs = iota(0, r.currEE.succs.length).array;
        foreach (i; isXor ? [0UL] : idcs[0 .. $])
          pidcs ~= comb(idcs, i + 1).array.dup;
        auto perms = pidcs.map!(a => a.map!(i => r.currEE.succs[i]).array).array;

        double[] probs;
        bool connProbsSet = r.currEE.asGate.probs.any!(p => p.prob > 0);
        for (size_t i = 0; i < perms.length; i++) {
          auto perm = perms[i];
          double total = cast(double) perm.fold!(delegate(t, eeID) {
            if (r.currEE.asGate.probs.canFind!(prob => prob.eeID == eeID))
              return t + r.currEE.asGate.probs.find!(prob => prob.eeID == eeID)[0].prob;
            else
              return t + (connProbsSet ? 0.0 : 1.0);
          })(0.0);
          probs ~= [total / cast(double) perm.length];
          // writeln("perm=", perm, ", total=", total);
        }

        // writeln("succs: ", r.currEE.succs);
        // writeln("perms: ", perms);
        // writeln("probs: ", probs);
        assert(!perms.empty);

        splits = perms[dice(probs)].array.dup;

        // splits = array(randomSample(r.currEE.succs, isXor ? 1 : uniform!"[]"(1, r.currEE.succs.length)));
        print(r.str ~ ", Chosen splits: " ~ text(splits));
        psim_.fos ~= [Simulation.SplitOption(r.id, r.currEE.id, splits.dup)];
      }
    }

    auto addToken = delegate Token(ulong bid) {
      tokens_ ~= new Token(r, bid);
      auto newToken = tokens_[$ - 1];
      if (!r.path.empty) {
        newToken.pathStart ~= r.path[0];
      }
      newToken.path = [[]];
      if (r.path.length > 1)
        newToken.path ~= r.path[1 .. $];
      return newToken;
    };

    foreach (bid; splits) {
      auto newToken = addToken(bid);
      newToken.lastEEID = r.currEE.id;
      if (fnOnTokenSplit)
        fnOnTokenSplit(r.time.func + r.time.queue, r.currEE.id, bid);
      if (isOr) {
        newToken.branchData ~= Token.BranchData(splits.length);
      }
    }

    // succLoop: foreach (su; r.currEE.succs) {
    //   foreach (sp; splits)
    //     if (sp == su)
    //       continue succLoop;
    //   auto newToken = addToken(su);
    // }

    tokens_ = tokens_.remove(tokenElemId--);
  }

  void onTokenJoin(ref int tokenElemId) {
    auto r = tokens_[tokenElemId];
    immutable bool isOr = r.currEE.asGate.type == Gate.Type.or;
    immutable bool isXor = r.currEE.asGate.type == Gate.Type.xor;
    immutable bool isAnd = (cast(Gate) r.currEE).type == Gate.Type.and;
    immutable auto tokensAtThisPos = tokens_.fold!((a, b) => r.id == b.id && b.currEE.id == r.currEE.id ? a + 1 : a)(
        0);

    size_t desiredTokensCount;
    if (isAnd)
      desiredTokensCount = r.currEE.deps.length;
    else if (isXor)
      desiredTokensCount = 1;
    else { // isOr
      assert(!r.branchData.empty, r.str ~ "'s branchData is empty");
      desiredTokensCount = r.branchData[$ - 1].concurrentCount;
    }

    if (tokensAtThisPos == desiredTokensCount) {
      // print(r.str ~ ": All of the " ~ text(desiredTokensCount) ~ " branches joined");
      ulong mtime = 0;
      Token mr = null;
      ulong[][] paths;
      for (int i = 0; i < tokens_.length; i++) {
        auto ri = tokens_[i];
        if (ri.id != r.id)
          continue;
        if (ri.currEE.id == r.currEE.id) {
          if (fnOnTokenJoin) {
            writeln("currEE: ", r.currEE.name, ", r.lastEE: ", r.lastEEID, ", ri.lastEE: ", ri.lastEEID);
            fnOnTokenJoin(ri.time.func + ri.time.queue, r.currEE.id, ri.lastEEID);
          }
          if (ri.time.func >= mtime) {
            mr = ri;
            mtime = ri.time.func;
          }
          paths ~= ri.path.dup;
          // result ~= rs[i].str ~ " joined\n";
          tokens_ = tokens_.remove(i--);
          tokenElemId--;
        }
      }

      // if (!isAnd) {
      //   // writeln("kick concurrentCounts=", mr.concurrentCounts[$ - 1]);
      //   mr.concurrentCounts = mr.concurrentCounts[0 .. $ - 1];
      // }
      if (isOr) {
        mr.branchData = mr.branchData[0 .. $ - 1];
      }

      tokens_ ~= new Token(mr, r.currEE.id);
      auto newToken = tokens_[$ - 1];
      newToken.step();

      if (!newToken.pathStart.empty) {
        newToken.path[0] = newToken.pathStart[$ - 1] ~ newToken.path[0]; // XXX
        newToken.pathStart = newToken.pathStart[0 .. $ - 1];
      }
      foreach (p; mr.path)
        paths = remove!(a => a == p)(paths);
      newToken.path ~= paths.dup;
    } else {
      // print(r.str ~ ": tokensAtThisPos="~text(tokensAtThisPos)~", desiredTokensCount="~text(desiredTokensCount));
    }
  }

  void onTokenEnd(ref int tokenElemId) {
    // writeln("RUNNER END !!! TIME=", tokens_[tokenElemId].time, "\n\n");
    print(tokens_[tokenElemId].str ~ " finished.");
    // tokenResults_[tokens_[tokenElemId].id] = tokens_[tokenElemId].str;
    tokens_ = tokens_.remove(tokenElemId--);
  }
}

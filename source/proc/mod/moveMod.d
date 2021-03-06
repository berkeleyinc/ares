module proc.mod.moveMod;

import proc.mod.modification;
import proc.businessProcess;
import proc.sim.simulation;

import std.algorithm.iteration;

class MoveMod : Modification {
  this(const EE from, const EE to, const EE bwStart, const EE bwEnd) {
    from_ = from;
    to_ = to;
    bwStart_ = bwStart;
    bwEnd_ = bwEnd;
  }

  override @property string toString() const {
    return "Move " ~ from_.name ~ " to " ~ to_.name ~ " in between " ~ bwStart_.name ~ " and " ~ bwEnd_.name;
  }

  override void apply(BusinessProcess p) {
    auto from = p(from_.id);
    auto to = p(to_.id);
    auto bwStart = p(bwStart_.id);
    auto bwEnd = p(bwEnd_.id);

    import std.algorithm.mutation : swap;
    import std.algorithm : canFind;

    if (bwStart.deps.canFind(bwEnd.id))
      swap(bwStart, bwEnd);

    void movePart(EE start, EE end, EE bwStart, EE bwEnd) {
      import std.algorithm.setops;

      with (p) {
        auto endAdapter = epcElements[end.succs[0]];
        endAdapter.deps = setDifference(endAdapter.deps.sort, [end.id]).array;
        endAdapter.deps ~= start.deps.dup; //[bwStart.id];

        bwEnd.deps = setDifference(bwEnd.deps.sort, [bwStart.id]).array;
        bwEnd.deps ~= end.id;

        start.deps = [bwStart.id].dup;

        postProcess();
      }
    }

    movePart(from, to, bwStart, bwEnd);
  }

  static Modification[] create(const BusinessProcess p, in Simulation defSim) {
    return (new MoveModFactory(p)).findMovements();
  }

private:
  const EE from_, to_, bwStart_, bwEnd_;

}

import proc.sim.multiple;
import proc.sim.simulator;
import proc.sim.simulation;
import std.typecons;
import std.array;
import std.algorithm;
import std.stdio;
import std.range;
import std.conv;

import util : mean;

private class MoveModFactory {
  this(const BusinessProcess p) {
    proc_ = p;
  }

  alias MembersFrontBack = Tuple!(ulong, "front", ulong, "back");

  Modification[] findMovements() {
    Modification[] pms;
    struct PathTime {
      double[][ulong] times; // time taken per path (identified by lastID)
      ulong startTime;
      ulong[] startIDs;
      ulong[ulong] startByLastID;
    }

    PathTime[ulong] pathTimesPerFork; // time per path, time is an array to handle possible loops
    auto sor = new Simulator(proc_);
    sor.fnOnTokenSplit = delegate(ulong currTime, ulong cID, ulong firstID) {
      auto conn = proc_(cID).asGate;
      if (conn.type != Gate.Type.and || conn.partner.isNull)
        return;
      // writeln("on token split cID=", cID, ", firstID=", firstID, ", has partner=", !conn.partner.isNull);

      if (conn.partner !in pathTimesPerFork) {
        pathTimesPerFork[conn.partner] = PathTime.init;
        pathTimesPerFork[conn.partner].startTime = currTime;
        // writeln("cID=", cID, ", conn.partner=", conn.partner);
      }
      // if (currTime != pathTimesPerFork[conn.partner].startTime) {
      //   throw new Exception("currTime=" ~ currTime.text ~ ", pathTimesPerFork[conn.partner].startTime="
      //       ~ pathTimesPerFork[conn.partner].startTime.text);
      // }
      pathTimesPerFork[conn.partner].startIDs ~= firstID;
    };
    sor.fnOnTokenJoin = delegate(ulong currTime, ulong cID, ulong lastID) {
      if (proc_(cID).asGate.type != Gate.Type.and || cID !in pathTimesPerFork)
        return;
      // writeln("on token join cID=", cID, ", lastID=", lastID, ", currTime=", currTime);

      pathTimesPerFork[cID].times[lastID] ~= [cast(double)(currTime - pathTimesPerFork[cID].startTime)];
      // XXX that's how we can find the right startID for the lastID
      if (lastID !in pathTimesPerFork[cID].startByLastID)
        foreach (possStartID; pathTimesPerFork[cID].startIDs) {
          // check if this startID is an element of the path from lastID back to the fork-gate
          auto pathObjs = proc_.listAllObjsBefore(proc_(lastID), typeid(EE), proc_(cID).asGate.partner) ~ [lastID];
          if (pathObjs.canFind(possStartID)) {
            pathTimesPerFork[cID].startByLastID[lastID] = possStartID;
            break;
          }
        }
      if (lastID !in pathTimesPerFork[cID].startByLastID) {
          throw new Exception("lastID !in pathTimesPerFork[cID].startByLastID");
      }
    };

    Simulation[] sims;
    // proc_.saveToFile("graph2.bin");
    MultiSimulator.allPathSimulate(sor, proc_, sims);
    // writeln("sims: ", sims);
    // foreach (i; 0 .. 1000) {
    //   sims ~= Simulation.def;
    //   sor.simulate(sims[i]);
    // }

    BusinessProcess clone = proc_.clone();
    foreach (cID; pathTimesPerFork.byKey().array.sort) {
      bool poss; // possible optimization found

      // do {
      alias TPB = Tuple!(ulong, "lastID", double, "time");
      TPB[] avTimePerBranch;
      poss = false;
      double maxTime;
      {
        ulong[] lastIDs;
        double[] times;
        foreach (lb; pathTimesPerFork[cID].times.byKeyValue()) {
          lastIDs ~= lb.key;
          times ~= lb.value.mean;
        }
        if (lastIDs.empty) {
          throw new Exception("no path times for fork " ~ text(cID));
        }

        maxTime = times.maxElement;
        foreach (i, t; times)
          avTimePerBranch ~= TPB(lastIDs[i], maxTime - t);
        // writeln("avTimePerBranch: ", avTimePerBranch);
      }
      // writeln("STARTSAR");
      // scope (exit) {
      // writeln("EXITSEX");
      // }

      auto connClose = proc_(cID).asGate;
      auto connOpen = proc_(connClose.partner).asGate;
      // writeln("conn=", conn.name);
      assert(!connOpen.partner.isNull);
      // XXX conn-partner conn switched
      ulong[] neighborIDs = proc_.listAllObjsAfter(connOpen, typeid(Function), (cast(ulong) connClose.id).nullable);
      MembersFrontBack memberIDs;
      size_t idxMax = avTimePerBranch.maxIndex!"a.time < b.time";
      // writeln("max=", avTimePerBranch[idxMax].time);
      auto last = proc_(avTimePerBranch[idxMax].lastID);

      // TODO TODO Movable entsprechend dependsOn von aktuellem Path einordnen
      // ulong[] funcsTillLast = proc

      double durOfMovable;
      poss = getMovable(true, connClose.id, neighborIDs, memberIDs, durOfMovable);
      // if (poss) {
      //   writeln("yes movable ", memberIDs.front, "|", memberIDs.back, " from cID=", connClose.id);

      //   writeln("durOfMovable: ", durOfMovable, "; avTimePerBranch[idxMax].time=", avTimePerBranch[idxMax].time);
      //   writeln(" avTimePerBranch=", avTimePerBranch);
      // }

      // bool poss2 = poss && avTimePerBranch[idxMax].time >= durOfMovable;
      // poss = getMovable(true, cID, neighborIDs, memberIDs, durOfMovable) && avTimePerBranch[idxMax].time >= durOfMovable;
      if (poss && avTimePerBranch[idxMax].time >= durOfMovable) {
        // writeln("YES! can move ", memberIDs.front, " -> ", memberIDs.back);
        pms ~= new MoveMod(proc_(memberIDs.front), proc_(memberIDs.back), last, connClose);
        // pathTimesPerFork[cID].times[memberIDs.back] = pathTimesPerFork[cID].times[last.id].map!(t => t + durOfMovable).array;
        // pathTimesPerFork[cID].times.remove(last.id);
        // pm_[$-1].apply(proc_);

        // proc_.movePart(proc_(memberIDs.front), proc_(memberIDs.back), last, conn);
      } else if (poss && durOfMovable <= maxTime) {
        // writeln("ALTERNATIVE! can move ", memberIDs.front, " -> ", memberIDs.back);
        pms ~= new MoveMod(proc_(memberIDs.front), proc_(memberIDs.back), connOpen, connClose);
      }

      foreach (i, nodeId; connClose.succs) {
        // TODO als seperator Path bei avTime <= maxTime
        poss = getMovable(true, connClose.id, neighborIDs, memberIDs, durOfMovable, i)
          && avTimePerBranch[idxMax].time >= durOfMovable;
        if (poss) {
          // writeln("YES!!! WANT move ", memberIDs.front, " to ", memberIDs.back, " between ",
          //     connOpen.name, " and ", connClose.name);
          pms ~= new MoveMod(proc_(memberIDs.front), proc_(memberIDs.back), connOpen, connClose);
        }
      }

      foreach (i, nodeId; connOpen.deps) {
        poss = getMovable(false, connOpen.id, neighborIDs, memberIDs, durOfMovable, i)
          && avTimePerBranch[idxMax].time >= durOfMovable;
        if (poss) {
          // writeln("YES!!! WANT(2) move ", memberIDs.front, " to ", memberIDs.back, " between ",
          //     connOpen.name, " and ", connClose.name);
          pms ~= new MoveMod(proc_(memberIDs.front), proc_(memberIDs.back), connOpen, connClose);
        }
      }

      poss = getMovable(false, connOpen.id, neighborIDs, memberIDs, durOfMovable);
      if (poss && avTimePerBranch[idxMax].time >= durOfMovable) {
        // writeln("YES! can ALSO move ", memberIDs.front, " -> ", memberIDs.back);
        pms ~= new MoveMod(proc_(memberIDs.front), proc_(memberIDs.back), connOpen,
            proc_(pathTimesPerFork[cID].startByLastID[last.id]));
        // pathTimesPerFork[cID].times[memberIDs.back] = pathTimesPerFork[cID].times[last.id].map!(t => t + durOfMovable).array;
        // pathTimesPerFork[cID].times.remove(last.id);
        // pm_[$-1].apply(proc_);
      } else if (poss && durOfMovable <= maxTime) {
        // writeln("ALTERNATIVE! can ALSO move ", memberIDs.front, " -> ", memberIDs.back);
        pms ~= new MoveMod(proc_(memberIDs.front), proc_(memberIDs.back), connOpen, connClose);
      }
      // static int ii = 0;
      // if (ii++ > 20)
      //   break;
      //}
      // while (poss);
    }

    return pms;
  }

  // finds IDs of first+last Elements from a movable entity (entity: Event + Function or AND/XOR/OR-Block) and their duration
  bool getMovable(bool right, in ulong fromID, in ulong[] newNeighborIDs, out MembersFrontBack memberIDs,
      out double durOfMovable, size_t pathIdx = 0) {
    import std.algorithm.mutation : swap;

    Rebindable!(const EE) next;
    const(ulong[])* pfollow;
    if (right) {
      if (proc_(fromID).succs.empty)
        return false;
      next = proc_(proc_(fromID).succs[pathIdx]);
      pfollow = &next.succs;
    } else {
      if (proc_(fromID).deps.empty)
        return false;
      next = proc_(proc_(fromID).deps[pathIdx]);
      pfollow = &next.deps;
    }

    if ((*pfollow).empty)
      return false;
    if (next.isFunc) {
      auto f = next.asFunc;
      bool someoneHasDeps = newNeighborIDs.filter!(nid => proc_(nid).isFunc)
        .any!(nid => proc_(nid).asFunc.dependsOn.canFind(f.id));
      if (someoneHasDeps)
        return false; // TODO the element after that might not have itself in someones deps
      if (f.dependsOn.any!(dep => newNeighborIDs.canFind(dep)))
        return false;
      durOfMovable = f.dur;
      memberIDs.front = f.id;
      memberIDs.back = (*pfollow)[0];
      if (!right)
        swap(memberIDs.front, memberIDs.back);
      return true;
    }
    if (next.isEvent && proc_((*pfollow)[0]).isFunc) {
      auto f = proc_((*pfollow)[0]).asFunc;
      if (f.dependsOn.any!(dep => newNeighborIDs.canFind(dep)))
        return false;
      durOfMovable = f.dur;
      memberIDs.front = next.id;
      memberIDs.back = f.id;
      if (!right)
        swap(memberIDs.front, memberIDs.back);
      return true;
    }
    if (next.isGate && (*pfollow).length > 1 && !next.asGate.partner.isNull) {
      // if (next.asGate.partner.isNull)
      //   return false;
      const Gate from = right ? next.asGate : proc_(next.asGate.partner).asGate, to = !right
        ? next.asGate : proc_(next.asGate.partner).asGate;

      // if (next.isGate && next.asGate.type == Gate.Type.xor)
      //   return false;
      // writeln("THIS CONN is FINE: ", from.name, " (to ", to.name, ")");
      ulong[] neighborIDs = proc_.listAllObjsAfter(from, typeid(Function), (cast(ulong) to.id).nullable);

      // if (fromID == 11 && from.id == 29) {
      //  writeln("neighborIDs: ", neighborIDs);
      //  writeln("newNeighborIDs: ", newNeighborIDs);
      //  writeln("right: ", right);
      //  assert(0, "NO!");
      //}

      // writeln("neighborIDs: ", neighborIDs);
      // if (right) {
      if (neighborIDs.any!(f => proc_(f).asFunc.dependsOn.any!(dep => newNeighborIDs.canFind(dep))))
        return false;
      //} else {
      if (newNeighborIDs.any!(f => proc_(f).asFunc.dependsOn.any!(dep => neighborIDs.canFind(dep))))
        return false;
      //}

      // proc_.saveToFile("test.bin");
      // writeln("startSimulation from=", from.name, " to ", to.name);
      // Simulation.allPathSimulate(proc_);
      durOfMovable = MultiSimulator.multiSimulate(proc_, 10, (cast(ulong) from.id).nullable,
          (cast(ulong) to.id).nullable);
      // writeln("simulation time=", durOfMovable);

      memberIDs.front = from.id;
      memberIDs.back = to.id;
      return true;
    }
    return false;
    // assert(0, "After a Join must come an Event and after an Event comes either a Function or a Split");
    // (all other semantics can be constructed from that)
  };

private:
  Rebindable!(const BusinessProcess) proc_;
}

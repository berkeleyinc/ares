module proc.sim.pathFinder;

import proc.businessProcess;

import std.algorithm : sort, map, canFind, any, filter, reduce;
import std.array : join, array;
import std.conv : text;
import std.stdio : writeln;
import std.range : empty;
import std.typecons : Tuple, tuple;

class PathFinder {
  this(const BusinessProcess proc) {
    this.process_ = proc;
  }

  private struct Path {
    // ulong time = 0;
    ulong[] visitedIds;
    ulong[] loopedFor;
    double runtimeMod = 1;

    // Path opAddAssign(const ref Path path) {
    //   time += path.time;
    //   return this;
    // }
  }

  Tuple!(ulong[], double)[] findPaths() {
    with (process_) {
      const auto ee = epcElements[getStartId()];

      Path path;
      findPaths(ee.succs[0], path);

      // paths_.sort!("a.time > b.time");
      // string pstr;
      // foreach (p; paths_)
      //   pstr ~= "\t" ~ text(p) ~ "\n";
      // writeln("EE_PATHS (" ~ text(paths_.length) ~ "):\n" ~ pstr);
    }
    return paths_.map!(p => tuple(p.visitedIds, p.runtimeMod)).array;
  }

private:
  const BusinessProcess process_;
  Path[] paths_;

  bool canHandleLoop(ref Path path, ulong nodeId, ulong prevID) {
    if (process_(nodeId).isGate && process_(nodeId).asGate.loopsFor.canFind(prevID)) {
      if (reduce!((a, b) => a + (b == prevID ? 1 : 0))(0, path.loopedFor) > 1) { //.filter!(a => a == prevID).array.length > 1) {
        // writeln("reached loopedFor: ", path.loopedFor);
        return false;
      } else {
        path.loopedFor ~= prevID;
        // writeln("loopedFor: ", path.loopedFor);
      }
    }
    return true;
  }

  void findPaths(ulong nodeId, ref Path path) {
    const EE ee = process_.epcElements[nodeId];
    assert(!ee.isAgent);

    if (ee.isFunc) {
      // writeln(bo.name ~ ", waiting for " ~ text((cast(Function) bo).dur));
      path.visitedIds ~= ee.id;
      // path.time += (cast(Function) ee).dur;
      if (!ee.succs.empty && canHandleLoop(path, ee.succs[0], ee.id)) {
        findPaths(ee.succs[0], path);
      }
    } else if (ee.isEvent) {
      path.visitedIds ~= ee.id;
      if (ee.succs.empty) {
        // reached END event
        paths_ ~= path;
      } else if (canHandleLoop(path, ee.succs[0], ee.id)) {
        findPaths(ee.succs[0], path);
      }
    } else if (ee.isGate) {
      auto gate = ee.asGate;

      path.visitedIds ~= gate.id;
      bool isSplit = gate.succs.length > 1;
      bool isAnd = gate.type == Gate.Type.and;
      bool isXor = gate.type == Gate.Type.xor;

      if (isSplit) {
        Path[] branchPaths;
        foreach (firstElemIdOfBranch; gate.succs) {
          //if (process_(o).isGate && process_(o).asGate.loopsFor.canFind(ee.id)) {
          //if (process_(o).succs.any!(sg => process_(sg).isGate && process_(sg).asGate.loopsFor.canFind(o))) {
          if (!canHandleLoop(path, firstElemIdOfBranch, gate.id)) {
            // writeln("SKIPPING LOOP");
            //paths_ ~= path;
            continue;
          }
          //Path newPath = path;

          import util;

          // create a copy of path
          Path newPath = path.gdup;
          if (!isAnd) {
            double sum = reduce!"a + b"(0.0, gate.probs.map!"a.prob");
            auto branchProb = gate.probs.filter!(a => a.nodeId == firstElemIdOfBranch).front.prob;
            newPath.runtimeMod *= branchProb / sum;
            if (newPath.runtimeMod < 0.05) // stop condition
              continue;
          } else {
            newPath.runtimeMod *= 1.0 / (cast(double) gate.succs.length);
          }

          // writeln("starting simulation of new path, start=" ~ process_.epcElements[o].name);
          findPaths(firstElemIdOfBranch, newPath);
          branchPaths ~= newPath;
          // writeln("simulated path: " ~ text(newPath));
        }

      } else { // JOIN / MERGE
        if (!ee.succs.empty && canHandleLoop(path, ee.succs[0], ee.id)) {
          findPaths(ee.succs[0], path);
        }
      }
    }
  }
}

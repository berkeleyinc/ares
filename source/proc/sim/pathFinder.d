module proc.sim.pathFinder;

import proc.businessProcess;

import std.algorithm : sort, map, canFind, any;
import std.array : join, array;
import std.conv : text;
import std.stdio : writeln;
import std.range : empty;

class PathFinder {
  this(const BusinessProcess proc) {
    this.process_ = proc;
  }

  struct Path {
    ulong time = 0;
    ulong[] allIDs;

    Path opAddAssign(const ref Path path) {
      time += path.time;
      return this;
    }

    // bool opEquals(ref const Path p) {
    //   if (time != p.time || fIDs.length != p.fIDs.length)
    //     return false;
    //   foreach (id1; fIDs)
    //     foreach (id2; p.fIDs)
    //       if (id1 != id2)
    //         return false;
    //   return true;
    // }
  }

  ulong[][] findPaths() {
    with (process_) {
      const auto ee = epcElements[getStartId()];
      // writeln("Found startObject " ~ bo.name);
      // writeln("succs: " ~ text(bo.succs));

      Path path;
      findPaths(ee.succs[0], path);

      // paths_.sort!("a.time > b.time");
      // string pstr;
      // foreach (p; paths_)
      //   pstr ~= "\t" ~ text(p) ~ "\n";

      // writeln("EE_PATHS (" ~ text(paths_.length) ~ "):\n" ~ pstr);
      //     ubyte[] data = process_.save();
      //     import std.file;

      //     write("bp.error.2", data);
    }
    return paths_.map!(p => p.allIDs).array;
  }

private:
  const BusinessProcess process_;
  Path[] paths_;

  void findPaths(ulong eeID, ref Path path, int subPath = 0, int stopOn = 0) {
    const EE ee = process_.epcElements[eeID];
    if (ee.isAgent) {
      return;
    }

    bool canFindPaths(ulong eeID, ulong prevID) {
      if (process_(eeID).isGate && process_(eeID).asGate.loopsFor.canFind(prevID))
        return false;
      return true;
      // if (process_(eeID).succs.any!(sg => process_(sg).isGate && process_(sg).asGate.loopsFor.canFind(eeID)))
      //   return;
    }

    // handle loops in EPCs
    // if (path.allIDs.canFind(eeID)) {
    //   // writeln("eeID ", eeID, " is already in path: ", path.allIDs);
    //   paths_ ~= path;
    //   return;
    // }

    // writeln("Next elem id=" ~ bo.name);
    // writeln("succs: " ~ text(bo.succs));
    if (ee.isFunc) {
      // writeln(bo.name ~ ", waiting for " ~ text((cast(Function) bo).dur));
      path.allIDs ~= ee.id;
      path.time += (cast(Function) ee).dur;
      //if (path.allIDs.find(bo.succs[0]).length <= 1)
      if (!ee.succs.empty && !path.allIDs.canFind(ee.succs[0]) && canFindPaths(ee.succs[0], ee.id))
        findPaths(ee.succs[0], path, subPath, stopOn);
      else {
        paths_ ~= path;
        return;
      }
    } else if (ee.isEvent) {
      path.allIDs ~= ee.id;
      if (ee.succs.empty) {
        paths_ ~= path;
        // writeln("reached END Event: " ~ text(bo.id));
        return;
      }
      //if (path.allIDs.find(bo.succs[0]).length <= 1)
      if (!path.allIDs.canFind(ee.succs[0]) && canFindPaths(ee.succs[0], ee.id)) {
        findPaths(ee.succs[0], path, subPath, stopOn);
      } else {
        paths_ ~= path;
        return;
      }
    } else if (ee.isGate) {

      path.allIDs ~= ee.id;
      bool isSplit = ee.succs.length > 1;
      bool isAnd = (cast(Gate) ee).type == Gate.Type.and;

      if (isSplit) {
        Path[] branchPaths;
        foreach (o; ee.succs) {
          //if (process_(o).isGate && process_(o).asGate.loopsFor.canFind(ee.id)) {
          //if (process_(o).succs.any!(sg => process_(sg).isGate && process_(sg).asGate.loopsFor.canFind(o))) {
          if (!canFindPaths(o, ee.id)) {
            writeln("SKIPPING LOOP");
            continue;
          }
          Path newPath = path;

          // writeln("starting simulation of new path, start=" ~ process_.epcElements[o].name);
          findPaths(o, newPath, subPath + 1, subPath + 1);
          branchPaths ~= newPath;
          // writeln("simulated path: " ~ text(newPath));
        }

        Path bigPath;
        foreach (p; branchPaths)
          if (p.time > bigPath.time)
            bigPath = p;
        // writeln("CHOSE bigPath: " ~ text(bigPath));
        path = bigPath;
        // writeln(">>> path += bigPath: " ~ text(path));

        const EE* lastEE = &process_.epcElements[bigPath.allIDs[$ - 1]];
        if (!lastEE.succs.empty) {
          //if (process_(lastEE.succs[0]).isGate && process_(lastEE.succs[0]).asGate.loopsFor.canFind(lastEE.id)) {

          if (!canFindPaths(lastEE.succs[0], lastEE.id)) {
            writeln("SKIPPING LOOP 2");
            //continue;
          } else
            findPaths(lastEE.succs[0], path, subPath + 1, stopOn);
        }
        if (!isAnd) {
          foreach (p; branchPaths) {
            if (p == bigPath)
              continue;
            const EE* lastEE2 = &process_.epcElements[p.allIDs[$ - 1]];
            if (!lastEE2.succs.empty) {
              // prevent stack overflow when processing loops
              // if (path.allIDs.canFind(lastEE2.succs[0]))
              //   continue;
              if (canFindPaths(lastEE2.succs[0], lastEE2.id))
                findPaths(lastEE2.succs[0], p, subPath + 1, 0);
            }
          }
        }
      } else {
        // writeln(bo.name ~ ", subPath=" ~ text(subPath));
        if (stopOn > 0 && stopOn == subPath)
          return;
        else {

          if (canFindPaths(ee.succs[0], ee.id))
            findPaths(ee.succs[0], path, subPath - 1, stopOn);
        }
      }
    }
  }
}

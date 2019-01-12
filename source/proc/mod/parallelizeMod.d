module proc.mod.parallelizeMod;

import proc.mod.modification;
import proc.businessProcess;
import proc.sim.simulation;

import std.range;
import std.algorithm;
import std.typecons;

class ParallelizeMod : Modification {
  this(const Function start, const Function end) {
    start_ = start;
    end_ = end;
  }

  override @property string toString() const {
    return "Parallelize from " ~ start_.name ~ " to " ~ end_.name;
  }

  override void apply(BusinessProcess proc) {
    auto start = proc(start_.id).asFunc;
    auto end = proc(end_.id).asFunc;

    const auto fids = [start.id] ~ proc.listAllObjsAfter(start, typeid(Function), end.id.nullable);
    Gate startConn = new Gate(Gate.Type.and);
    Gate endConn = new Gate(Gate.Type.and);

    // we assume that the fids array is in order: a -> b -> c -> d
    // auto f0Event = proc.getEventFromFunc(start);
    // if (!f0Event.deps.empty) {
    //   auto preObject = proc(f0Event.deps[0]); // can be Gate or Function
    //   startConn.deps = [preObject.id];
    // }
    proc.add([start.deps[0]], startConn);

    foreach (fid; fids) {
      auto fEvent = proc(proc(fid).succs[0]);
      proc(fid).deps = [startConn.id];
      endConn.deps ~= fEvent.id;
    }
    proc.add(endConn.deps, endConn);

    auto endEvent = proc(end.succs[0]);
    if (!endEvent.isEvent) {
      endConn.deps = endConn.deps.replace([endEvent.id], [end.id]);
      endEvent = end;
    }
    foreach (s; endEvent.succs) {
      proc(s).deps = proc(s).deps.replace([endEvent.id], [endConn.id]);
    }
    proc.postProcess();
  }

  static Modification[] create(const BusinessProcess p, in Simulation defSim) {
    return (new ParallelizeModFactory(p)).findParallelizations();
  }

private:
  Rebindable!(const Function) start_, end_;
}

import std.stdio;

private class ParallelizeModFactory {
  this(const BusinessProcess p) {
    proc_ = p;
  }

  Modification[] findParallelizations() {
    import std.random;

    Modification[] pms;
    immutable onlyOneStep = true;

    ulong[][] possiblePar;
    foreach (i, epcFunc; proc_.funcs) {
      auto preFuncIds = proc_(epcFunc.deps[0]).deps.find!((id) => proc_(id).isFunc);
      if (preFuncIds.empty)
        continue;
      assert(preFuncIds.length == 1);
      auto preFuncId = preFuncIds[0];
      // XXX do we need that check? vvv
      if (epcFunc.dependsOn.canFind(preFuncId))
        continue;
      bool didConcatenateFunc = false;

      ppFor: foreach (ref parFuncList; possiblePar) {
        if (parFuncList[0] == epcFunc.id) {
          // pp    ,  pre,f
          // [1, 0], [2, 1] 
          // 0 -> 1 -> 2
          // 2 depends on 0

          foreach (check; parFuncList)
            if (proc_(preFuncId).asFunc.dependsOn.canFind(check))
              continue ppFor;

          didConcatenateFunc = true;
          parFuncList = preFuncId ~ parFuncList;
        } else if (parFuncList[$ - 1] == preFuncId) {
          // pp    ,  pre,f
          // [0, 1], [1, 2] 
          // 0 -> 1 -> 2
          // 2 depends on 0

          foreach (check; parFuncList)
            if (epcFunc.dependsOn.canFind(check))
              continue ppFor;

          didConcatenateFunc = true;
          parFuncList ~= epcFunc.id;
        }
      }
      if (!didConcatenateFunc)
        possiblePar ~= [preFuncId, epcFunc.id];
    }

    // writeln("possiblePar: ", possiblePar);
    // TODO:
    //     possiblePar fine, but use [0] and [1] or [$-1] and [$-2] for ParaMods
    //     PathFinder, add arguments startID & endID
    /*

   [1,2,3], [4,5] ,[6,7,8,9]

   [1,2], [4,5], [6,7], [8,9]


*/

    // ulong[][] pidcs;
    // auto idcs = iota(0, possiblePar.length).array;
    // foreach (i; idcs[0 .. $])
    //   pidcs ~= comb(idcs, i + 1).array.dup;
    // auto perms = pidcs.map!(a => a.map!(i => possiblePar[i]).array).array;
    // writeln("perms: ", perms);

    // static if (onlyOneStep) {
    //   if (possiblePar.length >= 1)
    //     parallelize(randomSample(possiblePar, 1).front);
    //   return;
    // } else {

    foreach (pp; possiblePar) {
      foreach (ref pp2; possiblePar) {
        if (pp == pp2)
          continue;
        foreach (i, id; pp2) {
          if (pp.canFind(id)) {
            // TODO find out which pp should keep it
            // writeln("FOUND DUPLICATE ", id);
            pp2 = pp2.remove(i);
            break;
          }
        }
      }
    }

    foreach (pp; possiblePar) {
      if (pp.length == 1)
        continue;
      pms ~= new ParallelizeMod(proc_(pp[0]).asFunc, proc_(pp[$ - 1]).asFunc);
    }

    return pms;
  }

private:
  Rebindable!(const BusinessProcess) proc_;
}

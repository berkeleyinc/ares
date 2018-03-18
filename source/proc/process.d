module proc.process;

public import proc.businessObject;
public import proc.func;
public import proc.resource;
public import proc.event;
public import proc.gate;

import std.algorithm : canFind, sort, uniq, remove, each, find;
import std.algorithm.setops : setIntersection;
import std.stdio : writeln;
import std.conv : text;
import std.json;
import std.array;
import std.typecons : tuple, Nullable;
import std.range.primitives : empty;
import msgpack;

class Process {
  Function[] funcs;
  Resource[] ress;
  Event[] evts;
  Gate[] gates;

  @nonPacked BO[ulong] bos;

  ulong getStartId() const {
    // find START object
    foreach (o; bos.byValue()) {
      // it's the Object that has no dependent objects
      if (o.deps.length == 0)
        return o.id;
    }
    assert(0, "No startObject found");
  }

  ulong[] getEndIds() const {
    // find END events
    ulong[] endIds = [];
    fndLoop: foreach (o; bos.byValue()) {
      foreach (bo; bos.byValue()) {
        // only test first dep since Events can't have more than one dep
        if (bo.deps.length > 0 && bo.deps[0] == o.id)
          continue fndLoop;
      }
      endIds ~= o.id;
    }
    return endIds;
  }

  const(BO) opCall(ulong boID) const {
    if (boID !in bos)
      throw new Exception("boID " ~ text(boID) ~ " not an element of this process");
    return bos[boID];
  }

  BO opCall(ulong boID) {
    if (boID !in bos)
      throw new Exception("boID " ~ text(boID) ~ " not an element of this process");
    return bos[boID];
  }

  T add(T)(ulong[] deps, T obj) {
    BO[] matches;
    foreach (id; deps) {
      foreach (b; bos)
        if (id == b.id) {
          matches ~= b;
        }
      if (matches.length == 0)
        throw new Exception("add-Error: one of the deps cannot be found (id=" ~ text(id) ~ ")");
    }
    obj.id = objCounter_++;
    obj.deps = deps;
    // obj.deps = matches;
    bos[obj.id] = obj;

    static if (is(T == Function)) {
      funcs ~= obj;

      // // creating start event
      // if (obj.deps.length == 0) {
      //   auto evt = new Event;
      //   add([], evt);
      //   evt.name = "start";
      //   obj.deps ~= evt.id;
      // }

      // between two processes, there has to be an event
      if (matches.length > 0 && typeid(matches[0]) != typeid(Event)) {
        // writeln("Creating in-between Event for " ~ matches[0].name ~ " and " ~ text(obj.name));
        auto evt = new Event;
        add([], evt);
        foreach (m; matches) {
          if (typeid(m) == typeid(Function))
            bos[evt.id] = evt;
        }
        evt.deps = deps;
        // evt.deps = matches;
        obj.deps = [evt.id];
      }
    } else static if (is(T == Resource))
      ress ~= obj;
    else static if (is(T == Event))
      evts ~= obj;
    else static if (is(T == Gate))
      gates ~= obj;
    return obj;
  }

  ubyte[] save() const {
    return pack!false(this);
    //return cast(ubyte[]) pack!false(this).unpack().toJSONValue().toPrettyString();
  }

  override @property string toString() const {
    return pack!true(this).unpack().toJSONValue().toString();
  }

  bool hasSameStructure(const Process p) const {
    if (bos.length != p.bos.length)
      return false;
    foreach (ref bo; bos.byKeyValue()) {
      if (bo.value.deps != p.bos[bo.key].deps)
        return false;
    }
    return true;
  }

  // @property string toPrettyString() const {
  //   return pack!true(this).unpack().toJSONValue().toPrettyString();
  // }

  static Process load(ubyte[] bytes) {
    // auto bp = parseJSON(cast(string) bytes).fromJSONValue().as!Process();
    auto bp = unpack!(Process, false)(bytes);
    with (bp) {
      foreach (f; funcs)
        bos[f.id] = f;
      foreach (p; ress)
        bos[p.id] = p;
      foreach (e; evts)
        bos[e.id] = e;
      foreach (c; gates)
        bos[c.id] = c;

      postProcess();
    }
    return bp;
  }

  Process clone() const {
    return Process.load(save());
  }

  void postProcess() {
    // fill BO.succs
    foreach (bo; bos.byKeyValue()) {
      bo.value.succs = [];
      foreach (obj; bos.byKeyValue()) {
        if (canFind(obj.value.deps, bo.key) && !obj.value.isRes) {
          bo.value.succs ~= obj.key;
        }
      }
    }

    // set Function.ress 
    foreach (f; funcs) {
      ulong[] ps;
      foreach (p; ress)
        if (p.deps.canFind(f.id))
          ps ~= p.id;
      f.ress = ps;
    }

    // set Resource.quals
    foreach (ref p; ress) {
      foreach (pd; p.deps) {
        if (!p.quals.canFind(pd))
          p.quals ~= pd;
      }
    }

    // set Gate.probs
    foreach (ref c; gates) {
      if (c.succs.length < 2)
        continue;
      foreach (cs; c.succs) {
        if (c.type != Gate.Type.and && !c.probs.canFind!(a => a.boID == cs))
          c.probs ~= tuple!("boID", "prob")(cs, 1.0);
      }

      // TODO there has to be a better way
      bool removed;
      do {
        removed = false;
        foreach (i, cp; c.probs) {
          if (!c.succs.canFind(cp.boID)) {
            c.probs = c.probs.remove(i);
            removed = true;
            break;
          }
        }
      }
      while (removed);
    }

    import std.range : enumerate;
    import std.algorithm : minElement, map;
    import std.typecons : Tuple;

    // identify Gate loops
    foreach (ref c; gates) {
      immutable bool isSplit = c.succs.length > 1;
      if (!isSplit || c.type != Gate.Type.xor)
        continue;

      auto tillObjs = listAllObjs(c, typeid(Gate), true);

      foreach (i, cs; c.succs) {
        if (tillObjs.canFind(cs)) {
          writeln(c.name ~ " has loop branch " ~ bos[cs].name);
          c.loopsFor ~= cs;
          assert(bos[cs].deps.length > 1, "only support for loop branches without objs in between"); // TODO
          auto bconn = bos[cs].asGate;
          bconn.loopsFor ~= c.id;
        }
      }
    }

    // find Gate partners
    import util;

    gates.each!(c => c.partner.nullify());
    foreach (ref c; gates) {
      immutable bool isSplit = c.succs.length > 1;
      if (!isSplit || c.type == Gate.Type.xor)
        continue;
      Tuple!(size_t, "index", ulong, "value")[] checkArr;
      auto allAfter = c.succs.map!(cs => listAllObjs(bos[cs], typeid(Gate), false)).array;
      // ulong[][] cmbs;
      // for (size_t i = c.succs.length; i >= 2; i--)
      //   cmbs ~= comb(c.succs, i);
      // writeln("cmbs: ", cmbs);
      // foreach (i, cs; c.succs) {
      //   foreach (j, afterObj; allAfter[i]) {
      //   }
      // }

      //foreach (cmb; cmbs) {
      typeof(checkArr)[] afterConnsPerBranch;
      foreach (i, cs; c.succs) {
        // if (c.loopsFor.canFind(cs))
        //   continue;
        // listAllObjs preserves the order of found objects but for setIntersection, we need to sort the input arrays
        // to later restore the original found-order, we enumerate the results 
        auto branchObjs = allAfter[i].remove!(a => a == c.id || !bos[a].asGate.partner.isNull); // listAllObjs(bos[cs], typeid(Gate), false);
        // if (branchObjs.canFind(cs)) {
        //   bos[cs].asGate.loopsFor ~= cs;
        //   continue;
        // }
        afterConnsPerBranch ~= [branchObjs.enumerate.array.sort!"a.value < b.value".array];
        if (i > 0)
          checkArr = setIntersection!"a.value < b.value"(afterConnsPerBranch[i], checkArr).array;
        else
          checkArr = afterConnsPerBranch[0];
      }
      //   break;
      // if (!checkArr.empty) {
      //   checkArr = checkArr.sort!"a.index < b.index".array;
      //   writeln("cmb worked: ", cmb, " with ", checkArr.map!"a.value");
      //   break;
      // }
      //}
      // writeln("For ", c.name, ": ", afterConnsPerBranch);
      // XXX only with xor Gates you can build non-hierarchical layouts
      if (checkArr.empty && c.type != Gate.Type.xor) {
        throw new Exception("Can't find partner for " ~ c.name);
      }
      // assert(!checkArr.empty);
      if (checkArr.empty) {
        // writeln(c.name ~ " allAfter: ", allAfter);
        continue;
      }
      // checkArr = checkArr.sort!"a.index < b.index".array;
      // sizediff_t i = 0;
      // c.partner = checkArrs[i].value;
      // while (c.partner == c.id || !bos[c.partner].asGate.partner.isNull) {
      //   if (i + 1 == checkArrs.length) {
      //     writeln("checkArrs: ", checkArrs.map!(kv => kv.value));
      //     throw new Exception("Could not find partner for " ~ c.name);
      //   }
      //   c.partner = checkArrs[++i].value; // 
      // }
      c.partner = checkArr.minElement!"a.index < b.index".value;
      writeln("PARTNER FOR " ~ c.name ~ " is C" ~ c.partner.text);
      // if (c.id == c.partner)
      //   throw new Exception(c.name ~ " can't have itself as partner.");
      // if (!bos[c.partner].asGate.partner.isNull) {
      //   throw new Exception("C" ~ text(c.partner) ~ " has already C" ~ text(
      //       bos[c.partner].asGate.partner.get) ~ " -- couldn't find partner for " ~ c.name ~ ".");
      // }
      bos[c.partner].asGate.partner = c.id;

      // writeln("c.succs=", c.succs, ", checkArr.deps=", bos[checkArr[0]].deps);
      // XXX this happens when there is an additional edge to a join (e.g. part of a loop)
      // assert(c.succs.length == bos[checkArr[0]].deps.length, "Didn't find the right partner Gate for " ~ c.name);
    }

  }

  ulong[] listAllFuncsBefore(const BO bo) const {
    return listAllObjs(bo, typeid(Function), true);
  }

  ulong[] listAllEventsAfter(const BO bo) const {
    return listAllObjs(bo, typeid(Event), false);
  }

  ulong[] listAllObjsAfter(TI)(const BO bo, TI type, Nullable!ulong tillID = Nullable!ulong()) const {
    return listAllObjs(bo, type, false, tillID);
  }

  ulong[] listAllObjsBefore(TI)(const BO bo, TI type, Nullable!ulong tillID = Nullable!ulong()) const {
    return listAllObjs(bo, type, true, tillID);
  }

  void movePart(BO start, BO end, BO bwStart, BO bwEnd) {
    import std.algorithm.setops;

    auto endAdapter = bos[end.succs[0]];
    endAdapter.deps = setDifference(endAdapter.deps.sort, [end.id]).array;
    endAdapter.deps ~= start.deps.dup; //[bwStart.id];

    bwEnd.deps = setDifference(bwEnd.deps.sort, [bwStart.id]).array;
    bwEnd.deps ~= end.id;

    start.deps = [bwStart.id].dup;

    postProcess();
  }

  const(Event) getEventFromFunc(const Function f) const {
    return bos[find!((id) => bos[id].isEvent)(f.deps)[0]].asEvent;
  }

  Event getEventFromFunc(const Function f) {
    return bos[find!((id) => bos[id].isEvent)(f.deps)[0]].asEvent;
  }

private:
  ulong objCounter_ = 0;

  // lists all objects before/after bo. 
  ulong[] listAllObjs(TI)(const BO bo, TI type, bool before, Nullable!ulong tillID = Nullable!ulong()) const {
    void getObjs(ref ulong[] allIDs, ref ulong[] fids, const BO curr) {
      import std.traits;

      if (!tillID.isNull() && curr.id == tillID)
        return;
      foreach (d; before ? curr.deps : curr.succs) {
        // to handle Loops in the EPC
        if (allIDs.canFind(d) || curr.isGate && curr.asGate.loopsFor.canFind(d))
          continue;
        allIDs ~= d;

        const BO o = bos[d];
        static if (isArray!TI) {
          immutable rightType = type.canFind(typeid(o));
        } else {
          immutable rightType = type == typeid(BO) || type == typeid(o);
        }
        if (rightType)
          fids ~= d;
        getObjs(allIDs, fids, o);
      }
    }

    ulong[] fs, all;
    getObjs(all, fs, bo);
    return fs; //fs.sort.uniq.array;
  }
}

module proc.businessProcess;

public import proc.epcElement;
public import proc.func;
public import proc.agent;
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

class BusinessProcess {
  Function[] funcs;
  Agent[] agts;
  Event[] evts;
  Gate[] gates;

  @nonPacked EE[ulong] epcElements;

  ulong getStartId() const {
    // find START object
    foreach (o; epcElements.byValue()) {
      // it's the Object that has no dependent objects
      if (o.deps.length == 0)
        return o.id;
    }
    assert(0, "No startObject found");
  }

  ulong[] getEndIds() const {
    // find END events
    ulong[] endIds = [];
    fndLoop: foreach (o; epcElements.byValue()) {
      foreach (ee; epcElements.byValue()) {
        // only test first dep since Events can't have more than one dep
        if (ee.deps.length > 0 && ee.deps[0] == o.id)
          continue fndLoop;
      }
      endIds ~= o.id;
    }
    return endIds;
  }

  const(EE) opCall(ulong eeID) const {
    if (eeID !in epcElements)
      throw new Exception("eeID " ~ text(eeID) ~ " not an element of this process");
    return epcElements[eeID];
  }

  EE opCall(ulong eeID) {
    if (eeID !in epcElements)
      throw new Exception("eeID " ~ text(eeID) ~ " not an element of this process");
    return epcElements[eeID];
  }

  T add(T)(ulong[] deps, T obj) {
    EE[] matches;
    foreach (id; deps) {
      foreach (b; epcElements)
        if (id == b.id) {
          matches ~= b;
        }
      if (matches.length == 0)
        throw new Exception("add-Error: one of the deps cannot be found (id=" ~ text(id) ~ ")");
    }
    obj.id = objCounter_++;
    obj.deps = deps;
    // obj.deps = matches;
    epcElements[obj.id] = obj;

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
            epcElements[evt.id] = evt;
        }
        evt.deps = deps;
        // evt.deps = matches;
        obj.deps = [evt.id];
      }
    } else static if (is(T == Agent))
      agts ~= obj;
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

  bool hasSameStructure(const BusinessProcess p) const {
    if (epcElements.length != p.epcElements.length)
      return false;
    foreach (ref eePair; epcElements.byKeyValue()) {
      if (eePair.value.deps != p.epcElements[eePair.key].deps)
        return false;
    }
    return true;
  }

  // @property string toPrettyString() const {
  //   return pack!true(this).unpack().toJSONValue().toPrettyString();
  // }

  static BusinessProcess load(ubyte[] bytes) {
    // auto bp = parseJSON(cast(string) bytes).fromJSONValue().as!BusinessProcess();
    auto bp = unpack!(BusinessProcess, false)(bytes);
    with (bp) {
      foreach (f; funcs)
        epcElements[f.id] = f;
      foreach (p; agts)
        epcElements[p.id] = p;
      foreach (e; evts)
        epcElements[e.id] = e;
      foreach (c; gates)
        epcElements[c.id] = c;

      postProcess();
    }
    return bp;
  }

  BusinessProcess clone() const {
    return BusinessProcess.load(save());
  }

  void postProcess() {

    void updateSuccs() {
      // fill EE.succs
      foreach (ref eePair; epcElements.byKeyValue()) {
        eePair.value.succs = [];
        foreach (ref obj; epcElements.byKeyValue()) {
          if (canFind(obj.value.deps, eePair.key) && !obj.value.isAgent) {
            eePair.value.succs ~= obj.key;
          }
        }
      }
    }
    updateSuccs();

    // set Function.agts 
    foreach (f; funcs) {
      ulong[] ps;
      foreach (p; agts)
        if (p.deps.canFind(f.id))
          ps ~= p.id;
      f.agts = ps;
    }

    // set Agent.quals
    foreach (ref p; agts) {
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
        if (c.type != Gate.Type.and && !c.probs.canFind!(a => a.eeID == cs))
          c.probs ~= tuple!("eeID", "prob")(cs, 1.0);
      }

      // TODO there has to be a better way
      bool removed;
      do {
        removed = false;
        foreach (i, cp; c.probs) {
          if (!c.succs.canFind(cp.eeID)) {
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
          writeln(c.name ~ " has loop branch " ~ epcElements[cs].name);
          c.loopsFor ~= cs;
          // assert(epcElements[cs].deps.length > 1, "only support for loop branches without objs in between"); // TODO
          // auto bconn = epcElements[cs].asGate;
          // bconn.loopsFor ~= c.id;
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
      auto allAfter = c.succs.map!(cs => listAllObjs(epcElements[cs], typeid(Gate), false)).array;
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
        auto branchObjs = allAfter[i].remove!(a => a == c.id || !epcElements[a].asGate.partner.isNull); // listAllObjs(epcElements[cs], typeid(Gate), false);
        // if (branchObjs.canFind(cs)) {
        //   epcElements[cs].asGate.loopsFor ~= cs;
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
      // while (c.partner == c.id || !epcElements[c.partner].asGate.partner.isNull) {
      //   if (i + 1 == checkArrs.length) {
      //     writeln("checkArrs: ", checkArrs.map!(kv => kv.value));
      //     throw new Exception("Could not find partner for " ~ c.name);
      //   }
      //   c.partner = checkArrs[++i].value; // 
      // }
      c.partner = checkArr.minElement!"a.index < b.index".value;
      // writeln("PARTNER FOR " ~ c.name ~ " is G" ~ c.partner.text);
      // if (c.id == c.partner)
      //   throw new Exception(c.name ~ " can't have itself as partner.");
      // if (!epcElements[c.partner].asGate.partner.isNull) {
      //   throw new Exception("C" ~ text(c.partner) ~ " has already C" ~ text(
      //       epcElements[c.partner].asGate.partner.get) ~ " -- couldn't find partner for " ~ c.name ~ ".");
      // }
      epcElements[c.partner].asGate.partner = c.id;

      // writeln("c.succs=", c.succs, ", checkArr.deps=", epcElements[checkArr[0]].deps);
      // XXX this happens when there is an additional edge to a join (e.g. part of a loop)
      // assert(c.succs.length == epcElements[checkArr[0]].deps.length, "Didn't find the right partner Gate for " ~ c.name);
    }

    auto removeGateIDs = tuple!(long, long)(-1, -1);
    do {
      if (removeGateIDs[0] >= 0) {
        foreach (removeGateID; [removeGateIDs[0], removeGateIDs[1]].sort!"a > b") {
          auto id = gates[removeGateID].id;
          gates = gates.remove!(SwapStrategy.unstable)(removeGateID);
          writeln("Removing EPC_Element ", id, ", with deps=", epcElements[id].deps);
          epcElements.remove(id);
        }
        removeGateIDs[0] = -1;
        updateSuccs();
        // return;
      }

gateRemover:
      foreach (leftIDX, ref left; gates) {
        if (left.type != Gate.Type.and || left.partner.isNull || left.succs.length <= 1)
          continue;

        foreach (rightID; left.succs) { // TODO also for deps
          if (!epcElements[rightID].isGate)
            continue;
          auto right = epcElements[rightID].asGate;
          if (right.type != Gate.Type.and || right.partner.isNull || right.succs.length <= 1)
            continue;

          auto outerPartner = epcElements[left.partner].asGate;
          auto innerPartner = epcElements[right.partner].asGate;

          assert(innerPartner.succs.length == 1);
          assert(outerPartner.succs.length == 1);

          // innerPartner.deps = outerPartner.deps.dup;

          if (!outerPartner.deps.canFind(innerPartner.id))
            continue;

          writeln(left.id, ", left.deps=", left.deps, ", outer.deps=", outerPartner.deps);
          writeln(outerPartner.id, ", left.succs=", left.succs, ", outer.succs=", outerPartner.succs);

          right.deps = left.deps.dup; // OK
          foreach (s; left.succs)
            if (s != rightID)
              epcElements[s].deps = [rightID].dup; // OK
          removeGateIDs[0] = leftIDX;

          if (!outerPartner.succs.empty) {
            auto outerSucc = epcElements[outerPartner.succs[0]];
            outerSucc.deps = outerSucc.deps.remove!(a => epcElements[a].id == outerPartner.id);
            outerSucc.deps ~= innerPartner.id;
          }
          foreach (depID; outerPartner.deps)
            if (depID != innerPartner.id)
              innerPartner.deps ~= depID; // OK
          
          foreach (outerIDX, ref gate; gates)
            if (outerPartner.id == gate.id) {
              removeGateIDs[1] = outerIDX;
              break;
            }
          updateSuccs();
          writeln(right.id, ", right.deps=", right.deps, ", inner.deps=", innerPartner.deps);
          writeln(innerPartner.id, ", right.succs=", right.succs, ", inner.succs=", innerPartner.succs);

          break gateRemover;
        }
      }
    } while (removeGateIDs[0] != -1);

    import std.file;
    import graphviz.dotGenerator;

    string dot = generateDot(this);
    write("/tmp/graph2.dot", dot);

  }

  ulong[] listAllFuncsBefore(const EE ee) const {
    return listAllObjs(ee, typeid(Function), true);
  }

  ulong[] listAllEventsAfter(const EE ee) const {
    return listAllObjs(ee, typeid(Event), false);
  }

  ulong[] listAllObjsAfter(TI)(const EE ee, TI type, Nullable!ulong tillID = Nullable!ulong()) const {
    return listAllObjs(ee, type, false, tillID);
  }

  ulong[] listAllObjsBefore(TI)(const EE ee, TI type, Nullable!ulong tillID = Nullable!ulong()) const {
    return listAllObjs(ee, type, true, tillID);
  }

  void movePart(EE start, EE end, EE bwStart, EE bwEnd) {
    import std.algorithm.setops;

    auto endAdapter = epcElements[end.succs[0]];
    endAdapter.deps = setDifference(endAdapter.deps.sort, [end.id]).array;
    endAdapter.deps ~= start.deps.dup; //[bwStart.id];

    bwEnd.deps = setDifference(bwEnd.deps.sort, [bwStart.id]).array;
    bwEnd.deps ~= end.id;

    start.deps = [bwStart.id].dup;

    postProcess();
  }

  const(Event) getEventFromFunc(const Function f) const {
    return epcElements[find!((id) => epcElements[id].isEvent)(f.deps)[0]].asEvent;
  }

  Event getEventFromFunc(const Function f) {
    return epcElements[find!((id) => epcElements[id].isEvent)(f.deps)[0]].asEvent;
  }

private:
  ulong objCounter_ = 0;

  // lists all objects before/after bo. 
  ulong[] listAllObjs(TI)(const EE ee, TI type, bool before, Nullable!ulong tillID = Nullable!ulong()) const {
    void getObjs(ref ulong[] allIDs, ref ulong[] fids, const EE curr) {
      import std.traits;

      if (!tillID.isNull() && curr.id == tillID)
        return;
      foreach (d; before ? curr.deps : curr.succs) {
        // to handle Loops in the EPC
        if (allIDs.canFind(d) /*|| curr.isGate && curr.asGate.loopsFor.canFind(d)*/)
          continue;
        allIDs ~= d;

        const EE o = epcElements[d];
        static if (isArray!TI) {
          immutable rightType = type.canFind(typeid(o));
        } else {
          immutable rightType = type == typeid(EE) || type == typeid(o);
        }
        if (rightType)
          fids ~= d;
        getObjs(allIDs, fids, o);
      }
    }

    ulong[] fs, all;
    getObjs(all, fs, ee);
    return fs; //fs.sort.uniq.array;
  }
}

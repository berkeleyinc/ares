module proc.businessProcess;

public import proc.epcElement;
public import proc.func;
public import proc.agent;
public import proc.event;
public import proc.gate;

import std.algorithm : canFind, sort, uniq, remove, each, find, SwapStrategy;
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

  ulong getEndId() const {
    // find START object
    foreach (o; epcElements.byValue()) {
      // it's the Object that has no dependent objects
      if (!o.isAgent && o.succs.empty)
        return o.id;
    }
    assert(0, "No endObject found");
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

  const(EE) opCall(ulong nodeId) const {
    if (nodeId !in epcElements)
      throw new Exception("nodeId " ~ text(nodeId) ~ " not an element of this process");
    return epcElements[nodeId];
  }

  EE opCall(ulong nodeId) {
    if (nodeId !in epcElements)
      throw new Exception("nodeId " ~ text(nodeId) ~ " not an element of this process");
    return epcElements[nodeId];
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
      if (matches.length > 0 && !matches[0].isEvent) {
        // writeln("Creating in-between Event for " ~ matches[0].name ~ " and " ~ text(obj.name));
        if (matches[0].isGate && matches[0].asGate.type == Gate.Type.and) {
          // evt.deps = [obj.id];
        } else {
          auto evt = new Event;
          add([], evt);
          evt.deps = deps;
          obj.deps = [evt.id];
        }
      }
    } else static if (is(T == Agent))
      agts ~= obj;
    else static if (is(T == Event))
      evts ~= obj;
    else static if (is(T == Gate))
      gates ~= obj;
    return obj;
  }

  void saveToFile(string fileName = "bp.bin") const {
    import std.file;

    write("/tmp/" ~ fileName, save());
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
    scope (exit) {
      saveToFile("graph_after_process.bin");
    }

    void updateSuccs() {
      // fill EE.succs
      auto eekv = epcElements.byKeyValue();
      foreach (ref eePair; eekv) {
        eePair.value.succs = [];
        foreach (ref obj; eekv) {
          if (!obj.value.isAgent && canFind(obj.value.deps, eePair.key)) {
            eePair.value.succs ~= obj.key;
          }
        }
      }
    }

    void identifyGateLoops() {
      // identify Gate loops
      foreach (ref c; gates) {
        immutable bool isSplit = c.succs.length > 1;
        if (isSplit || c.type != Gate.Type.xor)
          continue;

        auto tillObjs = listAllObjsAfter(c, typeid(EE));
        // writeln("listAllAfter for ", c.name, ": ", tillObjs);

        foreach (i, cs; c.deps) {
          if (tillObjs.canFind(cs) && epcElements[cs].succs.canFind(c.id)) {
            // writeln(c.name ~ " has loop branch " ~ epcElements[cs].name);
            c.loopsFor ~= cs;
          }
        }
      }
    }

    void setGateProbs() {
      // set Gate.probs
      foreach (ref c; gates) {
        if (c.type == Gate.Type.and || c.succs.length < 2)
          continue;
        // TODO there has to be a better way
        bool removed;
        do {
          removed = false;
          foreach (i, cp; c.probs) {
            if (!c.succs.canFind(cp.nodeId)) {
              c.probs = c.probs.remove(i);
              removed = true;
              break;
            }
          }
        }
        while (removed);

        foreach (cs; c.succs) {
          if (!c.probs.canFind!(a => a.nodeId == cs))
            c.probs ~= tuple!("nodeId", "prob")(cs, 1.0);
          // TODO back propagation of probs 
        }
      }
    }

    void removeDuplicateAndGates() {
      auto removeGateIDs = tuple!(long, long)(-1, -1);
      do {
        if (removeGateIDs[0] >= 0) {
          foreach (removeGateID; [removeGateIDs[0], removeGateIDs[1]].sort!"a > b") {
            auto id = gates[removeGateID].id;
            gates = gates.remove!(SwapStrategy.unstable)(removeGateID);
            // writeln("Removing EPC_Element ", id, ", with deps=", epcElements[id].deps);
            epcElements.remove(id);
          }
          removeGateIDs[0] = -1;
          // return;
        }
        updateSuccs();

        gateRemover: foreach (leftIDX, ref left; gates) {
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

            assert(outerPartner.type == Gate.Type.and && innerPartner.type == Gate.Type.and);

            assert(innerPartner.succs.length == 1, "innerPartner.succs=" ~ innerPartner.succs.text);
            assert(outerPartner.succs.length == 1, "outerPartner.succs=" ~ outerPartner.succs.text);

            // innerPartner.deps = outerPartner.deps.dup;

            if (!outerPartner.deps.canFind(innerPartner.id))
              continue;

            // writeln(left.id, ", left.deps=", left.deps, ", outer.deps=", outerPartner.deps);
            // writeln(outerPartner.id, ", left.succs=", left.succs, ", outer.succs=", outerPartner.succs);

            right.deps = left.deps.dup; // OK
            foreach (s; left.succs)
              if (s != rightID)
                epcElements[s].deps = epcElements[s].deps.remove!(a => epcElements[a].id == left.id) ~ [rightID].dup; // OK
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
            // writeln(right.id, ", right.deps=", right.deps, ", inner.deps=", innerPartner.deps);
            // writeln(innerPartner.id, ", right.succs=", right.succs, ", inner.succs=", innerPartner.succs);

            break gateRemover;
          }
        }
      }
      while (removeGateIDs[0] != -1);
    }

    void findGatePartners() {
      import std.range : enumerate;
      import std.algorithm : minElement, map;
      import std.typecons : Tuple;

      // find Gate partners
      import util;

      gates.each!(c => c.partner.nullify());
      foreach (ref c; gates) {
        immutable bool isSplit = c.succs.length > 1;
        if (!isSplit || c.type == Gate.Type.xor)
          continue;
        Tuple!(size_t, "index", ulong, "value")[] checkArr;
        auto allAfter = c.succs.map!(cs => listAllObjsAfter(epcElements[cs], typeid(Gate))).array;
        // writeln("allAfter for each succ of ", c.name, ": ", allAfter);
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
          auto branchObjs = allAfter[i].remove!(a => a == c.id
              || epcElements[a].asGate.type != c.type || !epcElements[a].asGate.partner.isNull); // listAllObjs(epcElements[cs], typeid(Gate), false);
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
        if (checkArr.empty) {

          import std.file;
          import web.dotGenerator;

          string doto = generateDot(this);
          write("/tmp/graph.dot", doto);
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
    }

    void setFunctionAgts() {
      // set Function.agts 
      foreach (f; funcs) {
        ulong[] ps;
        foreach (p; agts)
          if (p.deps.canFind(f.id))
            ps ~= p.id;
        f.agts = ps;
      }
    }

    void setAgentQuals() {
      // set Agent.quals
      foreach (ref p; agts) {
        foreach (pd; p.deps) {
          if (!p.quals.canFind(pd))
            p.quals ~= pd;
        }
      }
    }

    void addEndEvent() {
      auto last = epcElements[getEndId()];
      if (!last.isEvent) {
        auto evt = add([last.id], new Event);
        last.succs = [evt.id];
      }
    }

    updateSuccs();

    addEndEvent();

    setFunctionAgts();
    setAgentQuals();

    findGatePartners();
    removeDuplicateAndGates();
    identifyGateLoops();
    setGateProbs();
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

  // const(Event) getEventFromFunc(const Function f) const {
  //   return epcElements[find!((id) => epcElements[id].isEvent)(f.succs)[0]].asEvent;
  // }

  // Event getEventFromFunc(const Function f) {
  //   return epcElements[find!((id) => epcElements[id].isEvent)(f.succs)[0]].asEvent;
  // }

private:
  ulong objCounter_ = 0;

  // lists all objects before/after bo. 
  ulong[] listAllObjs(TI)(const EE ee, TI type, bool before, Nullable!ulong tillID = Nullable!ulong()) const {
    void getObjs(ref ulong[] allIDs, ref ulong[] fids, const EE curr) {
      import std.traits;

      if (!tillID.isNull() && curr.id == tillID)
        return;
      addIDsLoop: foreach (d; before ? curr.deps : curr.succs) {
        // to handle Loops in the EPC
        bool contGetObjs = true;
        // foreach (checkLoopEl; before ? epcElements[d].deps : epcElements[d].succs) {
        //   if (epcElements[checkLoopEl].isGate && epcElements[checkLoopEl].asGate.loopsFor.canFind(d))
        //     contGetObjs = false;
        // }
        if (allIDs.canFind(d))
          continue;
        if (!before && epcElements[d].isGate && epcElements[d].asGate.loopsFor.canFind(curr.id) //

          

            || before && curr.isGate && curr.asGate.loopsFor.canFind(d)) //continue;
          contGetObjs = false;
        // if (d == ee.id)
        //   continue;
        allIDs ~= d;

        const EE o = epcElements[d];
        static if (isArray!TI) {
          immutable rightType = type.canFind(typeid(o));
        } else {
          immutable rightType = type == typeid(EE) || type == typeid(o);
        }
        if (rightType)
          fids ~= d;
        if (contGetObjs) {
          getObjs(allIDs, fids, o);
        }
      }
    }

    ulong[] fs, all;
    getObjs(all, fs, ee);
    return fs; //fs.sort.uniq.array;
  }
}

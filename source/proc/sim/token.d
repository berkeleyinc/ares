module proc.sim.token;

import proc.businessProcess;

import std.stdio : writeln;
import std.conv : text;
import std.algorithm;
import std.typecons;
import std.array;
import std.range.primitives : empty;

class Token {
  alias Queue = Token[][ulong];
  private static ulong uniqueIDCounter_ = 0;
  ulong uniqueID;
  // unittest {
  //   alias Queue = int[][int];

  //   static class AA {
  //     this(ref RefCounted!Queue arg) {
  //       a = arg;
  //     }
  //     void w() {
  //       a[1] = [42];
  //     }
  //     RefCounted!Queue a;
  //   }

  //   RefCounted!Queue aa;
  //   aa[6] = [666];
  //   writeln(aa);
  //   AA a = new AA(aa);
  //   a.w();
  //   writeln("a.a=",a.a);
  //   writeln("aa=",aa);
  //   assert(a.a == aa);
  //   

  // }
  this(void delegate(string) fprint, void delegate(ulong, ulong, ulong) fOnStartFunc, size_t id,
      const BusinessProcess p, ref Queue q, ulong bid, Nullable!ulong endID = Nullable!ulong.init) {
    this.uniqueID = uniqueIDCounter_++;
    this.id = id;
    currEE = p.epcElements[bid];
    process_ = p;
    queue_ = &q;
    print = fprint;
    onStartFunction = fOnStartFunc;
    endID_ = endID;
    // writeln("new Token " ~ text(id) ~ ", start=" ~ currEE.name);
  }

  void delegate(string) print;
  void delegate(ulong, ulong, ulong) onStartFunction;

  this(Token r, ulong bid) {
    this.uniqueID = uniqueIDCounter_++;
    process_ = r.process_;
    currEE = process_.epcElements[bid];
    queue_ = r.queue_;
    id = r.id;
    time = r.time;
    path ~= r.path;
    pathStart ~= r.pathStart;
    // concurrentCounts = r.concurrentCounts;
    branchData = r.branchData.dup;
    print = r.print;
    onStartFunction = r.onStartFunction;
    lastEEID = r.lastEEID;
    endID_ = r.endID_;
    // writeln("new split Token " ~ text(id) ~ ", start=" ~ currEE.name);
  }

  override bool opEquals(Object a) {
    if (typeid(a) == typeid(Token))
      return uniqueID == (cast(Token) a).uniqueID;
    return false;
  }

  // elapsed time with join-waiting
  Tuple!(ulong, "total", ulong, "func", ulong, "queue", ulong, "join") time;
  // ulong elapsedTotalTime = 0, elapsedFuncTime = 0;
  ulong[][] path;

  // LILO array
  ulong[][] pathStart;

  @property string str() {
    return "T_" ~ text(id) ~ "/" ~ text(uniqueID) ~ "(S:" ~ text(
        currState) ~ ", EE:" ~ currEE.name ~ ", " ~ text(path) ~ ", time[" ~ text(time.func) ~ "," ~ text(
        time.join) ~ "," ~ text(time.queue) ~ "," ~ text(time.total) ~ "], cont=" ~ text(
        continueTime) ~ ")" ~ (currState == State.wait ? ", " ~ text(currWaitState) : "");
  }

  enum State {
    wait,
    end,
    join,
    split,
    none
  }

  enum WaitState {
    inFunc,
    inQueue
  }

  void incTime(ulong step) {
    bool tokensInQueueOfCurrentFunc = currEE.isFunc ? currEE.asFunc.agts.any!(a => a in (*queue_)) : false;

    if (currEE.id !in (*queue_) && !tokensInQueueOfCurrentFunc) {
      // no tokens are in the queue of the current node or it's agents if it's a Function
      // then the token should just step over to the next node and not increase it's time
      return;
    }

    if (currState == State.wait) {
      if (currWaitState == WaitState.inFunc)
        time.func += step;
      else if (currWaitState == WaitState.inQueue)
        time.queue += step;
    } else if (currState == State.join)
      time.join += step;

    time.total += step;

    assert(time.total == time.join + time.queue + time.func);
  }

  @property ulong continueTime() {
    if (currState != State.wait)
      return 0;
    return continueTime_;
  }

  State poll(ulong currTime) {
    currentTime_ = currTime;
    if (currState == State.end || currState == State.wait && continueTime_ > currTime)
      return currState;
    if (currState == State.wait && currWaitState == WaitState.inQueue) {
      bool anyEmpty = currEE.asFunc.agts.any!(p => p !in *queue_ || (*queue_)[p].empty);
      if (anyEmpty && currEE.id in *queue_ && (*queue_)[currEE.id][0] == this) {
        // if currEE (waiting-) queue has elems but the agents queues not, fill Agent queue

        size_t p = currEE.asFunc.agts.find!(p => p in *queue_ && (*queue_)[p].empty)[0]; // there has to be an empty Agents queue
        (*queue_)[p] ~= this;
        (*queue_)[currEE.id] = (*queue_)[currEE.id][1 .. $];
        // print("filling agent queue:");
        startFunction(p);
      }
      // print("currEE=" ~ currEE.name ~ " inQueue");

      return State.wait;
    }
    if (currState == State.wait && currWaitState == WaitState.inFunc) {
      auto findMe = (size_t p) => !(*queue_)[p].empty && (*queue_)[p][0] == this;
      size_t p = currEE.asFunc.agts.find!findMe[0];
      (*queue_)[p] = (*queue_)[p][1 .. $];
      step();
    }

    return currState = getState();
  }

  void step() {
    if (!endID_.isNull && currEE.id == endID_) {
      currState = State.end;
      return;
    }

    // writeln("For ", c.name, ": ", afterConnsPerBranch);
    if (currEE.succs.empty) {
      ubyte[] data = process_.save();
      import std.file;

      write("bp.error", data);
      throw new Exception("currEE " ~ currEE.name ~ " succs.empty");
    }

    lastEEID = currEE.id;
    currEE = process_.epcElements[currEE.succs[0]];
    // writeln(str ~ ": next EE: " ~ currEE.name);
  }

  Rebindable!(const EE) currEE;
  State currState = State.none;
  WaitState currWaitState;
  size_t id;
  ulong lastEEID;

  // LILO array
  struct BranchData {
    // how many branches did we select (only for OR-Gate)
    size_t concurrentCount;
    // the uniqueID of the Token that splited this branch
    // ulong startID;
    // the first EE from the branch
    // ulong firstID;
  }
  // size_t[] concurrentCounts;
  BranchData[] branchData;

private:
  const BusinessProcess process_;
  Queue* queue_;
  ulong continueTime_ = 0;
  ulong currentTime_ = 0;
  Nullable!ulong endID_;

  void startFunction(ulong partID) {
    assert(currEE.isFunc);
    print("start " ~ currEE.name ~ ", with A" ~ text(partID));
    auto dur = currEE.asFunc.dur;
    if (onStartFunction)
      onStartFunction(partID, currentTime_, dur);

    continueTime_ = currentTime_ + dur;

    if (path.empty)
      path ~= [[]];
    path[0] ~= currEE.id;

    currWaitState = WaitState.inFunc;
  }

  State getState() {
    if (currEE.isFunc) {
      if (currEE.id !in (*queue_) || (*queue_)[currEE.id].empty)
        foreach (pid; currEE.asFunc.agts) {
          if (pid !in *queue_ || (*queue_)[pid].empty) {
            startFunction(pid);
            // writeln("PUTTING ", str, " INTO PID=", pid);
            (*queue_)[pid] ~= this;
            return State.wait;
          }
          // (*queue_)[currEE.id] ~= Token[].init;
        }

      continueTime_ = 0;

      // all Agents (agent.queue.length>1) are busy, so putting this Token into the queue of the current Function
      (*queue_)[currEE.id] ~= this;
      currWaitState = WaitState.inQueue;
      return State.wait;
    } else if (currEE.isEvent) {
      if (!currEE.succs.empty) {
        step();
        return getState();
      }

      // print(str ~ ": reached END Event: " ~ text(currEE.id));
      return currState = State.end;
    } else if (currEE.isGate) {
      bool isSplit = currEE.succs.length > 1;
      return isSplit ? State.split : State.join;
    }
    assert(0, "Token.step: invalid EE type " ~ text(typeid(currEE)));
  }

}

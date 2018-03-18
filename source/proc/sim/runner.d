module proc.sim.runner;

import proc.process;

import std.stdio : writeln;
import std.conv : text;
import std.algorithm;
import std.typecons;
import std.array;
import std.range.primitives : empty;

class Runner {
  alias Queue = Runner[][ulong];
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
  this(void delegate(string) fprint, void delegate(ulong, ulong, ulong) fOnStartFunc, size_t id, const Process p,
      ref Queue q, ulong bid, Nullable!ulong endID = Nullable!ulong.init) {
    this.uniqueID = uniqueIDCounter_++;
    this.id = id;
    currBO = p.bos[bid];
    process_ = p;
    queue_ = &q;
    print = fprint;
    onStartFunction = fOnStartFunc;
    endID_ = endID;
    // writeln("new Runner " ~ text(id) ~ ", start=" ~ currBO.name);
  }

  void delegate(string) print;
  void delegate(ulong, ulong, ulong) onStartFunction;

  this(Runner r, ulong bid) {
    this.uniqueID = uniqueIDCounter_++;
    process_ = r.process_;
    currBO = process_.bos[bid];
    queue_ = r.queue_;
    id = r.id;
    time = r.time;
    path ~= r.path;
    pathStart ~= r.pathStart;
    // concurrentCounts = r.concurrentCounts;
    branchData = r.branchData.dup;
    print = r.print;
    onStartFunction = r.onStartFunction;
    lastBOID = r.lastBOID;
    endID_ = r.endID_;
    // writeln("new split Runner " ~ text(id) ~ ", start=" ~ currBO.name);
  }

  override bool opEquals(Object a) {
    if (typeid(a) == typeid(Runner))
      return uniqueID == (cast(Runner) a).uniqueID;
    return false;
  }

  // elapsed time with join-waiting
  Tuple!(ulong, "total", ulong, "func", ulong, "queue", ulong, "join") time;
  // ulong elapsedTotalTime = 0, elapsedFuncTime = 0;
  ulong[][] path;

  // LILO array
  ulong[][] pathStart;

  @property string str() {
    return "R_" ~ text(id) ~ "/" ~ text(uniqueID) ~ "(S:" ~ text(
        currState) ~ ", BO:" ~ currBO.name ~ ", " ~ text(path) ~ ", time[" ~ text(time.func) ~ "," ~ text(
        time.join) ~ "," ~ text(time.queue) ~ "," ~ text(time.total) ~ "], cont=" ~ text(continueTime) ~ ")";
  }

  enum State {
    wait,
    end,
    join,
    next,
    split,
    none
  }

  enum WaitState {
    inFunc,
    inQueue
  }

  void incTime(ulong step) {
    bool runnersInQueueOfCurrentFunc = currBO.isFunc ? currBO.asFunc.ress.any!(a => a in (*queue_)) : false;
    if (currBO.id !in (*queue_) && !runnersInQueueOfCurrentFunc)
      return;

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
    if (currState == State.end)
      return State.end;
    if (currState == State.wait) {
      if (continueTime_ > currTime)
        return State.wait;
      int n = currBO.asFunc.ress.fold!((t, p) => (p in *queue_ && !(*queue_)[p].empty) ? t + 1 : t)(0);
      // n: how many Resource-queues are busy
      auto m = currBO.asFunc.ress.length;
      // writeln("N=" ~ text(n), ", M=", m);
      // assert(n <= 1);

      // find out if this Runner is the next entry in the queue for a specific p (Resource)
      auto findMe = (size_t p) => !(*queue_)[p].empty && (*queue_)[p][0] == this;

      bool myTurn = any!findMe(currBO.asFunc.ress);
      if (continueTime_ == 0) {
        // if we came up in the queue, we can start
        if (myTurn) {
          ulong nextPartID = currBO.asFunc.ress.find!findMe()[0];
          startFunction(nextPartID);
          return State.wait;
        }

        currWaitState = WaitState.inQueue;

        // any Resource queues of current Function is empty ?
        bool anyEmpty = currBO.asFunc.ress.any!(p => p !in *queue_ || (*queue_)[p].empty);
        if (anyEmpty && currBO.id in *queue_ && (*queue_)[currBO.id][0] == this) {
          // if currBO (waiting-) queue has elems but the resources queues not, fill Resource queue

          size_t p = currBO.asFunc.ress.find!(p => p in *queue_ && (*queue_)[p].empty)[0]; // there has to be an empty Resources queue
          (*queue_)[p] ~= this;
          (*queue_)[currBO.id] = (*queue_)[currBO.id][1 .. $];
        }

        return State.wait;
      }
      assert(myTurn);
      // find the queue which has this Runner
      size_t p = currBO.asFunc.ress.find!findMe[0];
      // remove this Runner from queue since continueTime < currTime (func time is up)
      (*queue_)[p] = (*queue_)[p][1 .. $];

      // putting next element into the now free queue from the queue of the current Function
      if ((*queue_)[p].empty) {
        if (currBO.id in (*queue_) && !(*queue_)[currBO.id].empty) {
          (*queue_)[p] ~= (*queue_)[currBO.id][0];
          (*queue_)[currBO.id] = (*queue_)[currBO.id][1 .. $];
        }
      }

      // writeln("bla step, r=" ~ str ~ ", continueTime=" ~ text(continueTime_));
      step();
    }

    currState = validateStep();

    if (currState == State.next) {
      step();
      return poll(currTime);
    }

    return currState;
  }

  void step() {
    if (!endID_.isNull && currBO.id == endID_) {
      currState = State.end;
      return;
    }

    // writeln("For ", c.name, ": ", afterConnsPerBranch);
    if (currBO.succs.empty) {
      throw new Exception("currBO " ~ currBO.name ~ " succs.empty");
    }

    lastBOID = currBO.id;
    currBO = process_.bos[currBO.succs[0]];
    // writeln(str ~ ": next BO: " ~ currBO.name);
  }

  void startFunction(ulong partID) {
    assert(currBO.isFunc);
    auto dur = currBO.asFunc.dur;
    if (onStartFunction)
      onStartFunction(partID, currentTime_, dur);

    continueTime_ = currentTime_ + dur;

    if (path.empty)
      path ~= [[]];
    path[0] ~= currBO.id;

    currWaitState = WaitState.inFunc;
  }

  State validateStep() {
    if (currBO.isFunc) {
      foreach (pid; currBO.asFunc.ress) {
        if (pid !in *queue_ || (*queue_)[pid].empty) {
          startFunction(pid);
          // writeln("PUTTING ", str, " INTO PID=", pid);
          (*queue_)[pid] ~= this;
          return State.wait;
        }
        // (*queue_)[currBO.id] ~= Runner[].init;
      }

      continueTime_ = 0;

      // all Resources (resource.queue.length>1) are busy, so putting this Runner into the queue of the current Function
      (*queue_)[currBO.id] ~= this;
      currWaitState = WaitState.inQueue;
      return State.wait;
    } else if (currBO.isEvent) {
      if (!currBO.succs.empty)
        return State.next;
      // print(str ~ ": reached END Event: " ~ text(currBO.id));
      return State.end;
    } else if (currBO.isGate) {
      bool isSplit = currBO.succs.length > 1;
      return isSplit ? State.split : State.join;
    }
    assert(0, "Runner.step: invalid BO type " ~ text(typeid(currBO)));
  }

  Rebindable!(const BO) currBO;
  State currState = State.none;
  WaitState currWaitState;
  size_t id;
  ulong lastBOID;

  // LILO array
  struct BranchData {
    // how many branches did we select (only for OR-Gate)
    size_t concurrentCount;
    // the uniqueID of the Runner that splited this branch
    // ulong startID;
    // the first BO from the branch
    // ulong firstID;
  }
  // size_t[] concurrentCounts;
  BranchData[] branchData;

private:
  const Process process_;
  Queue* queue_;
  ulong continueTime_ = 0;
  ulong currentTime_ = 0;
  Nullable!ulong endID_;
}

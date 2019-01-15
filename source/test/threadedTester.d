module test.threadedTester;

import core.thread;
import core.atomic;
import core.sync.mutex;
import std.container;
import std.range;
import std.stdio;
import std.conv : text;
import std.datetime;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.algorithm;

import test.businessProcessGenerator;
import proc.mod.businessProcessModifier;
import proc.sim.simulation;
import proc.sim.simulator;
import proc.sim.multiple;
import proc.sim.pathFinder;
import proc.businessProcess;

import util : gdup;
import config;

import core.memory;

class ThreadedTester {
  static @property ThreadedTester inst() {
    return _instance;
  }

  static void start(size_t bpCount, size_t threadCount, bool printMem) {
    auto cfg = Cfg.get().new Cfg.PerUser;
    ThreadedTester.runTester(cfg, threadCount);
    auto watch = StopWatch(AutoStart.yes);
    do {
      Thread.sleep(dur!("msecs")(100));

      ThreadedTester.popLogMessage(true);

      if (printMem) {
        GC.collect();
        auto runtime = watch.peek().total!"msecs";
        stderr.writeln("MM", GC.stats().usedSize, " ", runtime);
      }
    }
    while (inst._doneCounter <= bpCount);
    ThreadedTester.stopTester();
  }

  static void runTester(in Cfg.PerUser cfg, size_t threadCount) {
    if (_instance !is null)
      stopTester();
    _instance = new ThreadedTester(cfg, threadCount);
    with (_instance) {
      foreach (i; iota(0, _threadCount))
        _threads ~= new Thread(&run).start();
    }
  }

  static void stopTester() {
    if (_instance !is null)
      with (_instance) {
        _shouldStop = true;
        if (!stopped()) {
          foreach (ref th; _threads)
            try
              th.join(true);
            catch (Throwable exc)
              writeln("Rethrew exc: ", exc.text);
          Thread.sleep(dur!("msecs")(100));

          string result;

          result ~= "RT" ~ _runtimes.text ~ ", RTD" ~ _runtimeDiffs.text ~ "\n";
          result ~= "Total runtime of tester: " ~ _runtimeTimer.peek().text ~ "\n";
          result ~= "Total time spent for restructuring " ~ _runtimes.length.text ~ " BPs: " ~ (
              _runtimes.sum / _threadCount).text ~ "\n";
          // result ~= ""
          // result ~= "Amount of BusinessProcesses restructured: " ~ _runtimes.length.text ~ "\n";
          result ~= "Average runtime of restructuring: " ~ _runtimes.mean.text ~ "s, high/low: "
            ~ _runtimes.maxElement.text ~ "/" ~ _runtimes.minElement.text ~ "\n";
          result ~= "Average duration difference of restructured BPs: " ~ _runtimeDiffs.mean.text
            ~ " TE, high/low:" ~ _runtimeDiffs.maxElement.text ~ "/" ~ _runtimeDiffs.minElement.text ~ "\n";
          writeln(result);
          synchronized (_queueMtx)
            _queue.insertBack(result);

          // import core.stdc.stdlib;
          // exit(0);
        }
      }
    _instance = null;
    // GC.collect();
    // writeln("Memory usage: ", (GC.stats().usedSize / 1024.0), "kB");
  }

  static string popLogMessage(bool clear = false) {
    if (_instance is null || _instance._queue.empty)
      return "";
    with (_instance) {
      string str;
      synchronized (_queueMtx) {
        str = _queue.front();
        if (clear) {
          _queue.clear();
        } else
          _queue.removeFront();
      }
      return str;
    }
  }

  static bool stopped() {
    if (_instance is null)
      return true;
    return !_instance._threads.any!(th => th.isRunning);
  }

private:
  shared size_t _threadCount = 1;
  shared size_t _doneCounter = 0;
  shared bool _shouldStop = false;

  DList!string _queue;
  double[] _runtimes, _runtimeDiffs;
  const Cfg.PerUser _cfg;
  Thread[] _threads;
  static __gshared ThreadedTester _instance = null;
  Mutex _queueMtx, _rtMtx;
  StopWatch _runtimeTimer;

  this(const Cfg.PerUser cfg, size_t threadCount) {
    _cfg = cfg;
    _threadCount = threadCount;
    _queueMtx = new Mutex;
    _rtMtx = new Mutex;
    _runtimeTimer = StopWatch(AutoStart.yes);
  }

  static void run() {
    with (_instance) {
      double[] runtimes, runtimeDiffs;
      while (!_shouldStop) {
        auto proc = BusinessProcessGenerator.generate(_cfg);
        string result;
        const size_t tokenCount = _cfg[Cfg.R.SIM_parTokensPerSim].as!size_t;
        const auto timeBetween = _cfg[Cfg.R.SIM_timeBetweenTokenStarts].as!ulong;
        const Simulation defSim = Simulation.construct(tokenCount, timeBetween);

        auto m = new BusinessProcessModifier(proc, defSim);
        m.shouldStopFunc = { return ThreadedTester.inst._shouldStop; };
        auto watch = StopWatch(AutoStart.yes);
        try {
          auto newProcs = m.modify(_cfg, result);
          if (_shouldStop)
            break;
          auto runtime = watch.peek().total!"msecs";
          double runtimeDiff = 0;
          if (!newProcs.empty) {
            auto newProc = newProcs[0];
            validateBP(newProc);

            double timeTaken = MultiSimulator.allPathSimulate(proc);
            double timeTakenNew = MultiSimulator.allPathSimulate(newProc);
            // if (timeTakenNew - 3 > timeTaken) {
            //   import std.file;

            //   writeln("BP got worse?");
            //   write("/tmp/bp0.bin", proc.save());
            //   write("/tmp/bp1.bin", newProc.save());
            // }

            if (timeTakenNew >= timeTaken) {
              double[] simRuntimeDiffs;
              Simulator sor = new Simulator(null);
              foreach (i; iota(0, 500)) {
                Simulation sim = defSim.gdup;
                sor.process = proc;
                timeTaken = sor.simulate(sim);
                sor.process = newProc;
                timeTakenNew = sor.simulate(sim);
                simRuntimeDiffs ~= timeTaken - timeTakenNew;
              }
              runtimeDiff = simRuntimeDiffs.mean;
            } else
              runtimeDiff = timeTaken - timeTakenNew;

            // writeln("Found ", newProcs.length.text, " new BPs, runtime improval: ", runtimeDiff);
          } // else
          // writeln("No improved BPs found.");

          // const double N = 100, alpha = 2 / (N + 1);
          // runtimeAvg = alpha * double(botTick) + (1 - alpha) * RDAT->tick;

          runtimeDiffs ~= runtimeDiff;
          runtimes ~= runtime / 1000.0;

          synchronized (_queueMtx)
            _queue.insertBack(result);

          atomicOp!"+="(_doneCounter, 1);
        } catch (Throwable exc) {
          writeln("EXC: ", exc.text);
        }
      }

      synchronized (_rtMtx) {
        _runtimes ~= runtimes;
        _runtimeDiffs ~= runtimeDiffs;
      }
    }
  }

  void validateBP(const BusinessProcess bp) {

    class ConnExc : Exception {
      enum Type {
        functionHasAgents,
        // funcHasNoPredecessor,
        // funcHasNoSuccessor,
        eachAgentConnectedToAtLeastOneFunc,
        onlyOneEdgeOnEitherSide,
        // gateHasNoSuccessor,
        // gateHasNoPredecessor,
        decisionGateMustHaveEventOrGateSuccs,
        startOrEndMustBeEvent,
        onlyOneEndEventSupported,
        onlyOneStartEventSupported,
        eventPredecessorsMustBeFuncOrGate,
        eventSuccessorsMustBeFuncOrAndGate
      };

      this(Type type) {
        super(type.text);
        _type = type;
        bp.saveToFile("bpValidationErr." ~ type.text);
      }

      Type _type;
    }

    bool foundStartEvent = false, foundEndEvent = false;
    foreach (ref node; bp.epcElements.byValue()) {
      const EE[] prevs = bp.preNodes(node);
      const EE[] nexts = bp.succNodes(node);

      if (node.isFunc) {
        // if (prevs.filter!(ee => !ee.isAgent).array.length != 1)
        //   throw new ConnExc(ConnExc.Type.funcHasNoPredecessor);
        // if (nexts.length != 1)
        //   throw new ConnExc(ConnExc.Type.funcHasNoSuccessor);
        if (bp.agts.filter!(a => a.deps.any!(depId => depId == node.id)).empty)
          throw new ConnExc(ConnExc.Type.functionHasAgents);
      }
      if (node.isAgent) {
        if (!nexts.empty || prevs.empty || prevs.any!(ee => !ee.isFunc))
          throw new ConnExc(ConnExc.Type.eachAgentConnectedToAtLeastOneFunc);
      }
      if (node.isGate) {
        if (prevs.length > 1 && nexts.length > 1)
          throw new ConnExc(ConnExc.Type.onlyOneEdgeOnEitherSide);
        // if (prevs.empty)
        //   throw new ConnExc(ConnExc.Type.gateHasNoPredecessor);
        // if (nexts.empty)
        //   throw new ConnExc(ConnExc.Type.gateHasNoSuccessor);

        if (node.succs.length > 1 && (node.asGate.type == Gate.Type.or || node.asGate.type == Gate.Type.xor)) {
          if (nexts.any!(succ => !succ.isEvent && !succ.isGate))
            throw new ConnExc(ConnExc.Type.decisionGateMustHaveEventOrGateSuccs);
        }
      }

      if (!node.isAgent && (prevs.empty || nexts.empty)) {
        if (!node.isEvent)
          throw new ConnExc(ConnExc.Type.startOrEndMustBeEvent);
        if (nexts.empty) {
          if (foundEndEvent)
            throw new ConnExc(ConnExc.Type.onlyOneEndEventSupported);
          foundEndEvent = true;
        }
        if (prevs.empty) {
          if (foundStartEvent)
            throw new ConnExc(ConnExc.Type.onlyOneStartEventSupported);
          foundStartEvent = true;
        }
      }

      if (node.isEvent) {
        if (prevs.any!(ee => !ee.isFunc && !ee.isGate))
          throw new ConnExc(ConnExc.Type.eventPredecessorsMustBeFuncOrGate);
        if (nexts.any!(ee => !ee.isFunc && (!ee.isGate || ee.succs.length > 1 && ee.asGate.type != Gate.Type.and)))
          throw new ConnExc(ConnExc.Type.eventSuccessorsMustBeFuncOrAndGate);
      }
    }
  }
}

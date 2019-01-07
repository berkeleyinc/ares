module test.tester;

import core.thread;
import core.sync.mutex;
import std.container;
import std.range;
import std.stdio;
import std.conv : text;
import std.datetime;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.algorithm;

import config;
import test.businessProcessGenerator;
import proc.mod.businessProcessModifier;
import proc.sim.simulation;
import proc.sim.simulator;
import proc.sim.multiple;

import util : gdup;

class Tester {

  static void runTester(ref Cfg.PerUser cfg) {
    if (_instance !is null)
      stopTester();
    _instance = new Tester();
    with (_instance) {
      _cfg = cfg;
      //start();
      foreach (i; iota(0, 8))
        _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
      // _threads ~= new Thread(&run).start();
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

          string result;
          result ~= "Amount of BusinessProcesses restructured: " ~ _runtimes.length.text ~ "\n";
          result ~= "Average runtime of restructuring: " ~ _runtimes.mean.text ~ "s, high/low: "
            ~ _runtimes.maxElement.text ~ "/" ~ _runtimes.minElement.text ~ "\n";
          result ~= "Average duration difference of restructured BPs: " ~ _runtimeDiffs.mean.text
            ~ " TE, high/low:" ~ _runtimeDiffs.maxElement.text ~ "/" ~ _runtimeDiffs.minElement.text ~ "\n";
          writeln(result);
          synchronized (_queueMtx)
            _queue.insertBack(result);
        }
      }
  }

  static string popLogMessage() {
    with (_instance) {
      // if (stopped())
      //   return join(false).text;
      if (_queue.empty)
        return "";
      string str;
      synchronized (_queueMtx) {
        str = _queue.front();
        _queue.stableRemoveFront();
      }
      return str;
    }
  }

  static bool stopped() {
    return !_instance._threads.any!(th => th.isRunning);
  }

private:
  bool _shouldStop = false;
  DList!string _queue;
  double[] _runtimes, _runtimeDiffs;
  Cfg.PerUser _cfg;
  Thread[] _threads;
  static __gshared Tester _instance = null;
  Mutex _queueMtx;

  this() {
    //super(&run);
    _queueMtx = new Mutex;
  }

  static void run() {
    with (_instance) {
      const size_t tokenCount = _cfg[Cfg.R.SIM_parTokensPerSim].as!size_t;
      const auto timeBetween = _cfg[Cfg.R.SIM_timeBetweenTokenStarts].as!ulong;
      const Simulation defSim = Simulation.construct(tokenCount, timeBetween);

      double[] runtimes, runtimeDiffs;
      while (!_shouldStop) {
        auto proc = BusinessProcessGenerator.generate(_cfg);
        string result;
        auto m = new BusinessProcessModifier(proc, defSim);
        auto watch = StopWatch(AutoStart.yes);
        try {
          auto newProcs = m.modify(_cfg, result);
          if (!newProcs.empty) {
            auto newProc = newProcs[0];
            auto runtime = watch.peek().total!"msecs";
            runtimes ~= runtime / 1000.0;

            long[] simRuntimeDiffs;
            Simulator sor = new Simulator(null);
            foreach (i; iota(0, 50)) {
              Simulation sim = defSim.gdup;
              sor.process = proc;
              long timeTaken = sor.simulate(sim);
              sor.process = newProc;
              long timeTakenNew = sor.simulate(sim);
              simRuntimeDiffs ~= timeTaken - timeTakenNew;
            }

            runtimeDiffs ~= simRuntimeDiffs.mean;

            // synchronized (_queueMtx)
            _queue.insertBack(result);
          }
        } catch (Throwable exc) {
          writeln("EXC: ", exc.text);
        }
      }

      synchronized {
        _runtimes ~= runtimes;
        _runtimeDiffs ~= runtimeDiffs;
      }
    }
  }
}

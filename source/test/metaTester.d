module test.metaTester;

import test.threadedTester;
import std.process;
import std.conv;
static import std.file;
import std.string;
import std.algorithm;
import std.stdio;
import std.range;
import std.array;
import std.concurrency;
import core.thread;
import core.sync.mutex;

shared class MetaTester {
  static immutable string LogFileName = "test.log", MemDataFileName = "mprof.dat",
    ImprovRuntimeDataFileName = "rtprof.dat";
public:
  static void start(const string appName, size_t bpCount, size_t threadCount) {
    auto mt = new shared MetaTester(appName, bpCount, threadCount);
    foreach (i; iota(0, 5))
      mt.threadIds ~= cast(shared Tid) spawn(&MetaTester.worker, mt, i);
    foreach (tid; mt.threadIds)
      receiveOnly!int();
  }

private:
  shared this(const string appName, size_t bpCount, size_t threadCount) {
    foreach (fileName; [LogFileName, MemDataFileName, ImprovRuntimeDataFileName])
      std.file.write(fileName, "");

    this.appName = appName;
    this.bpCount = bpCount;
    this.threadCount = threadCount;
    logMtx = new shared Mutex;
  }

  // static double getMemOf(uint pid) {
  //   version (Windows) {
  //     // PROCESS_MEMORY_COUNTERS info;
  //     // GetProcessMemoryInfo(GetCurrentProcess(), &info, sizeof(info));
  //     // return cast(double) info.WorkingSetSize;
  //     return 0;
  //   }
  //   version (linux) {
  //     import core.sys.linux.unistd;

  //     ulong rss = 0;
  //     string statm = cast(string) std.file.read("/proc/" ~ pid.text ~ "/statm");
  //     auto pos = statm.indexOf(' ') + 1;
  //     rss = statm[pos .. pos + statm[pos .. $].indexOf(' ')].to!ulong;
  //     return (cast(double)(rss * cast(ulong) sysconf(_SC_PAGESIZE)) / 1024.0) / 1024.0;
  //   }
  // }

  static void worker(shared MetaTester thisPtr, size_t threadIdx) {
    scope (exit) {
      ownerTid.send(0);
    }
    // auto pin = pipe(), pout = pipe(), perr = pipe();
    // auto pid = spawnProcess(thisPtr.appName ~ " test " ~ thisPtr.bpCount.text ~ " " ~ thisPtr.threadCount.text,
    //     pin, pout, perr, Config.suppressConsole);
    auto aresPipe = pipeShell(thisPtr.appName ~ " test " ~ thisPtr.bpCount.text ~ " "
        ~ thisPtr.threadCount.text ~ " true");
    assert(!tryWait(aresPipe.pid).terminated);
    auto aresPid = aresPipe.pid.processID;

    const string titleStr = threadIdx.text ~ " Process-" ~ threadIdx.text ~ "\n";

    string plotMemData = titleStr.dup;
    size_t pidx = 0;
    while (!tryWait(aresPipe.pid).terminated) {
      string memInfoStr = aresPipe.stderr.readln().chomp();
      if (memInfoStr.length < 3)
        break;
      if (memInfoStr[0 .. 2] != "MM")
        continue;
      memInfoStr = memInfoStr[2 .. $];
      auto sepPos = memInfoStr.indexOf(' ');
      immutable ulong memInBytes = memInfoStr[0 .. sepPos].to!ulong;
      immutable double memInMb = ((cast(double) memInBytes) / 1024.0) / 1024.0;
      immutable double timeInSecs = (cast(double) memInfoStr[sepPos + 1 .. $].to!ulong) / 1000.0;

      // Thread.sleep(dur!("msecs")(cast(uint)(1000 * interval)));
      plotMemData ~= (pidx++ + 1).text ~ " " ~ threadIdx.text ~ " " ~ memInMb.text ~ " " ~ timeInSecs.text ~ "\n";
    }

    string[] output;
    foreach (line; aresPipe.stdout.byLine)
      output ~= line.idup;

    assert(output.length >= 6, "output[] error: " ~ output.join('\n') ~ " " ~ output.length.text);

    auto rtdStr = output[$ - 6];
    writeln("Process ", aresPid, " finished: ", rtdStr);
    auto rtdPos = rtdStr.indexOf("RTD[");
    assert(rtdPos > 0, "Didn't find RuntimeDiff array in stdout of ThreadedTester");
    rtdStr = rtdStr[rtdPos + 4 .. $];
    rtdStr = rtdStr[0 .. rtdStr.indexOf("]")];
    string plotImprovData = titleStr.dup;
    auto vals = rtdStr.splitter(", ").map!(val => val.to!double).array.sort.array;
    int i = 0;
    double[] leftVals = vals[0] ~ generate!(() => vals[i += 2]).take(vals.length / 2 - 2).array;
    i = 1;
    double[] rightVals = generate!(() => vals[i += 2]).take(vals.length / 2 - 2).array.reverse.array ~ vals[1];

    vals = leftVals ~ rightVals;

    pidx = 0;
    foreach (rtd; vals) {
      plotImprovData ~= (pidx++ + 1).text ~ " " ~ threadIdx.text ~ " " ~ rtd.text ~ "\n";
    }

    synchronized (thisPtr.logMtx) {
      std.file.write(LogFileName, std.file.read(LogFileName) ~ output[$ - 4 .. $].join("\n") ~ "\n");
      std.file.write(MemDataFileName, std.file.read(MemDataFileName) ~ plotMemData ~ "\n\n\n");
      std.file.write(ImprovRuntimeDataFileName, std.file.read(ImprovRuntimeDataFileName) ~ plotImprovData ~ "\n\n\n");
    }

  }

  Tid[] threadIds;
  string appName;
  Mutex logMtx;
  size_t bpCount, threadCount;
}

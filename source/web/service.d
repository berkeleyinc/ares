module web.service;

import std.file : read, write;
import std.json;
import std.array : join;
import std.exception;
import std.algorithm;
import std.conv : text;
import std.stdio : writeln;
import std.typecons : Nullable, Tuple, tuple;
import std.math : abs;
import std.parallelism : parallel;
import std.datetime;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.range : iota;

import web.sessions;
import web.dotGenerator;

import test.threadedTester;
import test.businessProcessExamples;
import gen = test.businessProcessGenerator;

import proc.businessProcess;
import proc.sim.simulator;
import proc.sim.simulation;
import proc.mod.businessProcessModifier;

import vibe.vibe;
import msgpack;

import config;

class WebService {
  private {
    SessionVar!(string, "sid") sessionID_;
    SessionVar!(string, "dot") dot_;
    SessionVar!(DotGeneratorOptions, "dotGenOpts") dotGenOpts_;
    SessionVar!(size_t, "bpID") bpID_ = 0;
    @noRoute {
      @property BusinessProcess process() {
        if (Sessions.get(sessionID_).bps.length <= bpID_)
          throw new Exception("bpID " ~ bpID_.text ~ " not valid.");
        return Sessions.get(sessionID_).bps[bpID_];
      }

      @property process(BusinessProcess bp) {
        if (bpID_ >= processCount) {
          bpID_ = processCount;
          Sessions.get(sessionID_).bps ~= bp;
        }
        Sessions.get(sessionID_).bps[bpID_] = bp;
      }

      @property size_t processCount() {
        return Sessions.get(sessionID_).bps.length;
      }
    }
  }

  void index(HTTPServerRequest req, HTTPServerResponse res) {
    if (!req.session) {
      sessionID_ = "";
      sessionID_ = req.session.id;
      logInfo("creating new Session " ~ sessionID_);
      Sessions.create(sessionID_);
      // Sessions.get(sessionID_).bps = [];
      process = gen.BusinessProcessGenerator.generate(Sessions.get(sessionID_).cfg);
      // process = gen.BusinessProcessGenerator.generate();

      //auto p = assignAgentExample(false);

      // auto p = dilemmaExample();

      //process = p;

      dot_ = generateDot(process, dotGenOpts_);
    }
    bpID_ = 0;
    size_t bpCount = processCount;
    size_t sessionCount = Sessions.sessionCount;
    render!("index.dt", bpCount, sessionCount);
  }

  @method(HTTPMethod.GET) @path("/new_session") void resetSession(HTTPServerRequest req, HTTPServerResponse res) {
    Sessions.terminateSessions(); // this resets all sessions

    if (req.session)
      res.terminateSession();
    res.redirect("/");
  }

  void getConfig(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody(Sessions.get(sessionID_).cfg.toString, "text/plain");
  }

  void getJson(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody(process.toString(), "application/json");
  }

  @method(HTTPMethod.GET)
  @path("/set_config") void setConfig(HTTPServerRequest req, HTTPServerResponse res, string key, string val) {
    writeln(__FUNCTION__, ": key=", key, ", val=", val);
    if (val.length > 42)
      throw new Exception("Value too long");

    auto cfg = Sessions.get(sessionID_).cfg;
    if (cfg.get.exists(key))
      cfg.get.put(key, val);

    res.writeBody("OK", "text/plain");
  }

  @method(HTTPMethod.GET)
  @path("/set_object_config") void setObjectConfig(HTTPServerRequest req, HTTPServerResponse res,
      ulong id, Nullable!int did, Nullable!int dur, Nullable!int qid, Nullable!double p, Nullable!ulong oid) {
    auto el = process.epcElements[id];

    void applyChange(ref ulong[] arr, ulong id) {
      foreach (removeIdx, arrId; arr)
        if (id == arrId) {
          arr = arr.remove(removeIdx);
          return;
        }
      arr ~= id;
    }

    if (el.isFunc) {
      if (!did.isNull) {
        writeln("Changing dependsOn of Function ", id, ", adding ", did);
        applyChange(el.asFunc.dependsOn, did);
      }
      if (!dur.isNull) {
        el.asFunc.dur = dur;
      }
    } else if (el.isAgent) {
      writeln("Changing qual/assignment of Agent ", id, ", QID=", qid, ", DID=", did);
      if (!qid.isNull)
        applyChange(el.asAgent.quals, qid);
      else {
        applyChange(el.deps, did);
        process.postProcess();
      }
    } else if (el.isGate) {
      writeln("Changing branch probs of Gate ", id, ", oid=", oid, ", newProb=", p);
      foreach (ref pe; el.asGate.probs)
        if (pe.nodeId == oid)
          pe.prob = p;
    }
    res.writeBody("OK", "text/plain");
  }

  void getObjectConfig(HTTPServerRequest req, HTTPServerResponse res, ulong id) {
    // logInfo(__FUNCTION__ ~ " --> id=" ~ text(id) ~ ", sid=" ~ req.session.id);
    if (!Sessions.exists(req.session.id) || id !in process.epcElements)
      return;

    auto el = process.epcElements[id];
    JSONValue json;

    string className;

    string packWithType() {
      string packWithType(string c) {
        return "if (typeid(el) == typeid(" ~ c ~ ")) {" ~ "className = " ~ c ~ ".stringof;"
          ~ "json = pack!true(cast(" ~ c ~ ") el).unpack().toJSONValue();" ~ "}";
      }

      string res;
      foreach (e; [Function.stringof, Event.stringof, Gate.stringof, Agent.stringof])
        res ~= packWithType(e);
      return res;
    }

    mixin(packWithType());

    json["class"] = className;

    if (el.isFunc) {
      const auto fs = process.listAllFuncsBefore(el);
      // writeln("\n\nBWFORE: ", fs);
      json["beforeFuncs"] = fs;
    } else if (el.isAgent) {
      ulong[] fs;
      foreach (nodeId; process.epcElements.byKey())
        if (process.epcElements[nodeId].isFunc)
          fs ~= nodeId;
      json["allFuncs"] = fs;
    }

    res.writeBody(json.toString(), "application/json");
  }

  @method(HTTPMethod.GET) @path("/download/ares.bin") void download(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody(cast(string) process.save(), "application/octet-stream");
  }

  @method(HTTPMethod.POST) @path("/upload") void upload(HTTPServerRequest req, HTTPServerResponse res) {
    writeln(__LINE__);
    // File upload here
    auto file = "ares.bin" in req.files;
    try {
      writeln(__LINE__);
      process = BusinessProcess.load(cast(ubyte[]) read(file.tempPath.toString));
      writeln(__LINE__);

      // dot_ = generateDot(process, dotGenOpts_);
      // getGraph(req, res, "dot");

      getGraph(req, res, -1);
      writeln(__LINE__);
    } catch (Throwable t) {
      writeln("Err: " ~ t.text);
    }
  }

  void getGraph(HTTPServerRequest req, HTTPServerResponse res, int id) {
    scope (exit) {
      res.writeBody(dot_, "text/plain");
    }

    if (id >= 0 && id != bpID_) {
      bpID_ = id;
    }

    dot_ = generateDot(process, dotGenOpts_);
  }

  @method(HTTPMethod.GET)
  @path("/set/dot") void setDotOption(HTTPServerRequest req, HTTPServerResponse res, DotGeneratorOptions opts) {

    const Session session = req.session;
    if (!session) {
      logError(__FUNCTION__ ~ ": no valid session");
      return;
    }
    DotGeneratorOptions dotGenOpts = dotGenOpts_;
    if (opts.showAgents)
      dotGenOpts.showAgents = !dotGenOpts_.showAgents;
    dotGenOpts_ = dotGenOpts;

    res.writeBody("OK", "text/plain");
  }

  @method(HTTPMethod.GET) @path("/clone") void clone(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);
    auto baseBP = process;
    bpID_ = processCount;
    process = baseBP.clone();
    dot_ = generateDot(process, dotGenOpts_);
    res.writeBody(dot_, "text/plain");
  }

  @method(HTTPMethod.GET) @path("/res") void restructureBusinessProcess(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);
    // auto newBusinessProcess = process.clone();

    const size_t tokenCount = Sessions.get(sessionID_).cfg[Cfg.R.SIM_parTokensPerSim].as!size_t;
    const auto timeBetween = Sessions.get(sessionID_).cfg[Cfg.R.SIM_timeBetweenTokenStarts].as!ulong;
    Simulation defSim = Simulation.construct(tokenCount, timeBetween);

    JSONValue json;
    auto m = new BusinessProcessModifier(process, defSim);

    string result;

    string[] dots;
    auto newProcs = m.modify(Sessions.get(sessionID_).cfg, result);
    foreach (i, p; newProcs) {
      dots ~= generateDot(p, dotGenOpts_);
      Sessions.get(sessionID_).bps ~= p;
      bpID_ = bpID_ + 1;
    }

    json["log"] = result;
    json["dots_len"] = dots.length;
    res.writeBody(json.toString(), "application/json");
  }

  @method(HTTPMethod.GET)
  @path("/gen") void generateBusinessProcess(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);
    bpID_ = 0;
    sessionID_ = req.session.id;
    Sessions.get(req.session.id).bps = [];
    // Sessions.get().bpsBySid[req.session.id].clear();

    void fn_exitScope() {
      JSONValue json;
      dot_ = generateDot(process, dotGenOpts_);
      json["log"] = "Created " ~ text(process.funcs.length) ~ " Functions, " ~ text(
          process.gates.length) ~ " Gates and " ~ text(process.agts.length) ~ " Agents.";
      json["dot"] = dot_.dup;
      res.writeBody(json.toString(), "application/json");
    }

    scope (exit)
      fn_exitScope();

    process = gen.BusinessProcessGenerator.generate(Sessions.get(sessionID_).cfg);
  }

  @method(HTTPMethod.GET) @path("/testStop") void testRestructureStop(HTTPServerRequest req, HTTPServerResponse res) {
    ThreadedTester.stopTester();
    res.writeBody("0", "text/plain");
  }

  @method(HTTPMethod.GET) @path("/test") void testRestructureStart(HTTPServerRequest req,
      HTTPServerResponse res, Nullable!bool log) {
    // bpID_ = 0;
    sessionID_ = req.session.id;
    // Sessions.get(req.session.id).bps = [];

    if (!log.isNull() && log) {
      auto msg = ThreadedTester.popLogMessage();
      if (msg.empty && ThreadedTester.stopped)
        msg = "EOF";
      res.writeBody(msg, "text/plain");
    } else {
      ThreadedTester.runTester(Sessions.get(sessionID_).cfg, 8);
      res.writeBody("Starting tester...", "text/plain");
    }
  }

  @method(HTTPMethod.GET) @path("/sim/start") void startSimulation(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);

    const size_t simCount = Sessions.get(sessionID_).cfg[Cfg.R.SIM_simsPerBP].as!size_t;
    const size_t tokenCount = Sessions.get(sessionID_).cfg[Cfg.R.SIM_parTokensPerSim].as!size_t;
    const auto timeBetween = Sessions.get(sessionID_).cfg[Cfg.R.SIM_timeBetweenTokenStarts].as!ulong;
    string msg = "Running " ~ simCount.text ~ " simulations per BP with " ~ tokenCount.text ~ " tokens each ...\n";

    Simulation defSim = Simulation.construct(tokenCount, timeBetween);

    double[] times;
    times.length = processCount;
    times[] = 0.0;

    const(BusinessProcess)[] ps = Sessions.get(req.session.id).bps;

    auto sw = StopWatch(AutoStart.yes);
    foreach (i; 0 .. simCount) {
      import util;

      Simulation sim = defSim.gdup;
      Simulator sor = new Simulator(null);

      // foreach (i; parallel(iota(0, simCount))) {
      foreach (bpID, const ref bp; ps) {
        if (!Sessions.get(sessionID_).cfg[Cfg.R.SIM_reuseChosenPaths].as!bool)
          sim = defSim.gdup;
        // result ~= "BP " ~ text(bpID) ~ "\n";
        sor.process = bp;
        auto timeTaken = sor.simulate(sim);

        // import proc.sim.multiple;
        // auto timeTaken = MultiSimulator.allPathSimulate(sor, bp, defSim);
        synchronized {
          times[bpID] += timeTaken;
        }
        // result ~= "\n";
      }
    }

    // msg ~= result ~"\n\n";
    // msg ~= "BP times: " ~ text(times) ~ "\n";
    msg ~= "BP times: " ~ text(times.map!(a => a / simCount)) ~ "\n";
    msg ~= "Runtime: " ~ text(sw.peek()) ~ "\n";

    res.writeBody(msg, "text/plain");
  }
}

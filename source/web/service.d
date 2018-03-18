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
import graphviz.dotGenerator;

import proc.process;

import gen = proc.generator;
import proc.sim.simulator;
import proc.sim.simulation;
import proc.mod.modifier;

import vibe.vibe;
import msgpack;

import config;

class WebService {
  private {
    SessionVar!(string, "sid") sessionID_;
    SessionVar!(string, "dot") dot_;
    SessionVar!(DotGeneratorOptions, "dotGenOpts") dotGenOpts_;
    SessionVar!(size_t, "bpID") bpID_ = 0;
  }

  @noRoute {
    @property Process process() {
      if (Sessions.get(sessionID_).bps.length <= bpID_)
        throw new Exception("bpID " ~ bpID_.text ~ " not valid.");
      return Sessions.get(sessionID_).bps[bpID_];
    }

    @property process(Process bp) {
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

  void index(HTTPServerRequest req, HTTPServerResponse res) {
    if (!req.session) {
      sessionID_ = "";
      sessionID_ = req.session.id;
      logInfo("creating new Session " ~ sessionID_);
      Sessions.create(sessionID_);
      // Sessions.get(sessionID_).bps = [];
      //process = gen.Generator.generate();

      Process p = new Process;
      auto e0 = p.add([], new Event);
      auto f1 = p.add([e0.id], new Function);
      p.add([f1.id], new Resource);
      auto c3 = p.add([f1.id], new Gate(Gate.Type.xor));
      auto e4 = p.add([c3.id], new Event);
      auto e5 = p.add([c3.id], new Event);
      auto f6 = p.add([e4.id], new Function);
      auto p7 = p.add([f6.id], new Resource);
      auto f8 = p.add([e5.id], new Function);
      p.add([f8.id], new Resource);
      auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.xor));
      auto e11 = p.add([c10.id], new Event);
      auto f12 = p.add([e11.id], new Function);
      p7.asRes.quals ~= f12.id; 
      p.add([f12.id], new Resource);
      // auto e13 = p.add([f12.id], new Event);
      auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
      auto e15 = p.add([c14.id], new Event);
      auto f16 = p.add([e15.id], new Function);
      p.add([f16.id], new Resource);
      c10.deps ~= f16.id;
      auto e18 = p.add([c14.id], new Event);
      p.postProcess();

      process = p;

      dot_ = generateDot(process, dotGenOpts_);
    }
    bpID_ = 0;
    size_t bpCount = processCount;
    size_t sessionCount = Sessions.sessionCount;
    render!("index.dt", bpCount, sessionCount);
  }

  @method(HTTPMethod.GET) @path("/new_session")
  void resetSession(HTTPServerRequest req, HTTPServerResponse res) {
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

  @method(HTTPMethod.GET) @path("/set_config")
  void setConfig(HTTPServerRequest req, HTTPServerResponse res, string key, string val) {
    writeln(__FUNCTION__, ": key=", key, ", val=", val);
    if (val.length > 42)
      throw new Exception("Value too long");

    auto cfg = Sessions.get(sessionID_).cfg;
    if (cfg.get.exists(key))
      cfg.get.put(key, val);

    res.writeBody("OK", "text/plain");
  }

  @method(HTTPMethod.GET) @path("/set_object_config")
  void setObjectConfig(HTTPServerRequest req, HTTPServerResponse res, ulong id, Nullable!int did,
      Nullable!int dur, Nullable!int qid, Nullable!double p, Nullable!ulong oid) {
    auto el = process.bos[id];

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
    } else if (el.isRes) {
      writeln("Changing qual/assignment of Resource ", id, ", QID=", qid, ", DID=", did);
      if (!qid.isNull)
        applyChange(el.asRes.quals, qid);
      else {
        applyChange(el.deps, did);
        process.postProcess();
      }
    } else if (el.isGate) {
      writeln("Changing branch probs of Gate ", id, ", oid=", oid, ", newProb=", p);
      foreach (ref pe; el.asGate.probs)
        if (pe.boID == oid)
          pe.prob = p;
    }
    res.writeBody("OK", "text/plain");
  }

  void getObjectConfig(HTTPServerRequest req, HTTPServerResponse res, ulong id) {
    // logInfo(__FUNCTION__ ~ " --> id=" ~ text(id) ~ ", sid=" ~ req.session.id);
    if (!Sessions.exists(req.session.id) || id !in process.bos)
      return;

    auto el = process.bos[id];
    JSONValue json;

    string className;

    string packWithType() {
      string packWithType(string c) {
        return "if (typeid(el) == typeid(" ~ c ~ ")) {" ~ "className = " ~ c ~ ".stringof;"
          ~ "json = pack!true(cast(" ~ c ~ ") el).unpack().toJSONValue();" ~ "}";
      }

      string res;
      foreach (e; [Function.stringof, Event.stringof, Gate.stringof, Resource.stringof])
        res ~= packWithType(e);
      return res;
    }

    mixin(packWithType());

    json["class"] = className;

    if (el.isFunc) {
      const auto fs = process.listAllFuncsBefore(el);
      // writeln("\n\nBWFORE: ", fs);
      json["beforeFuncs"] = fs;
    } else if (el.isRes) {
      ulong[] fs;
      foreach (boID; process.bos.byKey())
        if (process.bos[boID].isFunc)
          fs ~= boID;
      json["allFuncs"] = fs;
    }

    res.writeBody(json.toString(), "application/json");
  }

  @method(HTTPMethod.GET) @path("/download/ares.bin")
  void download(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody(cast(string) process.save(), "application/octet-stream");
  }

  void postUpload(HTTPServerRequest req, HTTPServerResponse res) {
    // File upload here
    auto file = "ares.bin" in req.files;
    process = Process.load(cast(ubyte[]) read(file.tempPath.toString));

    // dot_ = generateDot(process, dotGenOpts_);
    // getGraph(req, res, "dot");

    getGraph(req, res, -1);
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

  @method(HTTPMethod.GET) @path("/set/dot")
  void setDotOption(HTTPServerRequest req, HTTPServerResponse res, DotGeneratorOptions opts) {

    const Session session = req.session;
    if (!session) {
      logError(__FUNCTION__ ~ ": no valid session");
      return;
    }
    DotGeneratorOptions dotGenOpts = dotGenOpts_;
    if (opts.showParts)
      dotGenOpts.showParts = !dotGenOpts_.showParts;
    dotGenOpts_ = dotGenOpts;

    res.writeBody("OK", "text/plain");
  }

  @method(HTTPMethod.GET) @path("/clone")
  void clone(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);
    auto baseBP = process;
    bpID_ = processCount;
    process = baseBP.clone();
    dot_ = generateDot(process, dotGenOpts_);
    res.writeBody(dot_, "text/plain");
  }

  @method(HTTPMethod.GET) @path("/res")
  void restructureProcess(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);
    // auto newProcess = process.clone();

    const size_t runnerCount = Sessions.get(sessionID_).cfg[Cfg.R.SIM_parRunnersPerSim].as!size_t;
    const auto timeBetween = Sessions.get(sessionID_).cfg[Cfg.R.SIM_timeBetweenRunnerStarts].as!ulong;
    Simulation defSim = Simulation.construct(runnerCount, timeBetween);

    JSONValue json;
    Modifier m = new Modifier(process, defSim);

    string result;

    string[] dots;
    auto newProcs = m.modify(result);
    foreach (i, p; newProcs) {
      dots ~= generateDot(p, dotGenOpts_);
      Sessions.get(sessionID_).bps ~= p;
      bpID_ = bpID_ + 1;
    }

    json["log"] = result;
    json["dots_len"] = dots.length;
    res.writeBody(json.toString(), "application/json");
  }

  @method(HTTPMethod.GET) @path("/gen")
  void generateProcess(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);
    bpID_ = 0;
    sessionID_ = req.session.id;
    Sessions.get(req.session.id).bps = [];
    // Sessions.get().bpsBySid[req.session.id].clear();

    process = gen.Generator.generate(Sessions.get(sessionID_).cfg);
    dot_ = generateDot(process, dotGenOpts_);
    JSONValue json;
    json["log"] = "Created " ~ text(process.funcs.length) ~ " Functions, " ~ text(
        process.gates.length) ~ " Gates and " ~ text(process.ress.length) ~ " Resources.";
    json["dot"] = dot_.dup;
    res.writeBody(json.toString(), "application/json");
  }

  @method(HTTPMethod.GET) @path("/sim/start")
  void startSimulation(HTTPServerRequest req, HTTPServerResponse res) {
    logInfo(__FUNCTION__);

    const size_t simCount = Sessions.get(sessionID_).cfg[Cfg.R.SIM_simsPerBP].as!size_t;
    const size_t runnerCount = Sessions.get(sessionID_).cfg[Cfg.R.SIM_parRunnersPerSim].as!size_t;
    const auto timeBetween = Sessions.get(sessionID_).cfg[Cfg.R.SIM_timeBetweenRunnerStarts].as!ulong;
    string msg = "Running " ~ simCount.text ~ " simulations per BP with " ~ runnerCount.text ~ " Runners each ...\n";

    Simulation defSim = Simulation.construct(runnerCount, timeBetween);

    ulong[] times;
    times.length = processCount;

    const(Process)[] ps = Sessions.get(req.session.id).bps;

    auto sw = StopWatch(AutoStart.yes);
    foreach (i; 0 .. simCount) {
      import opmix.dup;

      Simulation sim = defSim.gdup;
      Simulator sor = new Simulator(null);

      // foreach (i; parallel(iota(0, simCount))) {
      foreach (bpID, const ref bp; ps) {
        if (!Sessions.get(sessionID_).cfg[Cfg.R.SIM_reuseChosenPaths].as!bool)
          sim = defSim.gdup;
        // result ~= "BP " ~ text(bpID) ~ "\n";
        sor.process = bp;
        auto timeTaken = sor.simulate(sim);
        synchronized {
          times[bpID] += timeTaken;
        }
        // result ~= "\n";
      }
    }
    // msg ~= result ~"\n\n";
    msg ~= "BP times: " ~ text(times.map!(a => cast(double) a / cast(double) simCount)) ~ "\n";
    msg ~= "Runtime: " ~ text(sw.peek()) ~ "\n";

    res.writeBody(msg, "text/plain");
  }
}

module config;

import std.array;
import std.file : write, read;
import std.conv : text;
import std.algorithm : map, each;
import std.stdio;
import std.traits : EnumMembers;

import std.json;
public import jsonwrap;

// JSONValue[] to T[]
T[] nodeArr(T)(ref const JSONValue n) {
  return n.array().map!(a => a.as!T.value)().array;
}

class Cfg {
  static ~this() {
  }

  class PerUser {
    this() {
      // TODO maybe better deep copy
      fromString(rRoot().toString);
    }

    @property ref JSONValue get() {
      return root_;
    }

    ref const(JSONValue) opIndex(R key) const {
      immutable skey = text(key);
      if ((skey in root_) is null) {
        // root_[skey] = Cfg.get[key];
        return Cfg.get[key];
      }
      return root_[skey];
    }

    void fromString(string inp) {
      root_ = parseJSON(inp);
    }

    @property override string toString() {
      return root_.toString;
    }

    private JSONValue root_;
  }

  // General config entry
  enum G {
    VER, //
    SRV_port, // server daemon port
    SRV_listenIP // listen IP (additional to localhost)
  }

  // Runtime config entry
  enum R {
    GEN_branchTypeProbs, // xor,and,or,seq,loop probs (in %)
    GEN_branchCountProbs, // branch-count probs
    GEN_avgFuncDurs, // average function durations (bottom,top limit)
    GEN_maxDepth, // max depth of generated graphs
    GEN_maxFuncs, // max function count of generated graphs
    // GEN_agentAssignProbs, // 
    SIM_simsPerBP, // run simulations per BP
    SIM_parTokensPerSim, // how many tokens to start per simulation
    SIM_timeBetweenTokenStarts, // time between start of runners 
    SIM_reuseChosenPaths, // Simulator will choose same paths from first BP (BP 1)

    MOD_useMoveMod,
    MOD_useParallelizeMod,
    MOD_useAssignMod
  }

  immutable static string configFileName = "config.js";

  static @property Cfg get() {
    if (!instantiated_)
      synchronized (Cfg.classinfo) {
        if (!instance_)
          instance_ = new Cfg();
        instantiated_ = true;
      }
    return instance_;
  }

  ref JSONValue opIndex() {
    return root_;
  }

  ref JSONValue opIndex(G key) {
    return gRoot[text(key)];
  }

  ref JSONValue opIndex(R key) {
    return rRoot[text(key)];
  }

  @property ref JSONValue rRoot() {
    return root_["Runtime"];
  }

  @property ref JSONValue gRoot() {
    return root_["General"];
  }

  @property override string toString() {
    return Cfg.get[].toString;
  }

private:
  this() {
    bool save = false;
    try {
      root_ = parseJSON(cast(string) read(configFileName));
    } catch (Exception e) {
      writeln("Creating new " ~ configFileName ~ ".");
      root_ = JSONValue((int[string]).init);
      root_["General"] = (int[string]).init;
      root_["Runtime"] = (int[string]).init;
      save = true;
    }
    [EnumMembers!G].each!(e => opIndex(e, Cfg.def(e)));
    [EnumMembers!R].each!(e => opIndex(e, Cfg.def(e)));
    if (save)
      write(configFileName, root_.toPrettyString);
  }

  ref JSONValue opIndex(T)(T key, JSONValue val) {
    static if (is(T == G))
      JSONValue* root = &gRoot();
    else
      JSONValue* root = &rRoot();
    immutable skey = text(key);
    if ((skey in *root) is null) {
      (*root)[skey] = val;
    }
    return (*root)[skey];
  }

  static JSONValue def(G ce) {
    final switch (ce) {
    case G.VER:
      return JSONValue("0.1");
    case G.SRV_port:
      return JSONValue(8080);
    case G.SRV_listenIP:
      return JSONValue("");
    }
  };
  static JSONValue def(R ce) {
    final switch (ce) {
    case R.MOD_useMoveMod:
      return JSONValue(true);
    case R.MOD_useParallelizeMod:
      return JSONValue(true);
    case R.MOD_useAssignMod:
      return JSONValue(true);
    case R.GEN_branchTypeProbs:
      return JSONValue([20.0, 8.0, 8.0, 60.0, 15.0]);
    case R.GEN_branchCountProbs:
      return JSONValue([64.0, 25.0, 10.0, 3.0]);
    case R.GEN_avgFuncDurs:
      return JSONValue([1, 4]);
    case R.GEN_maxDepth:
      return JSONValue(7);
    case R.GEN_maxFuncs:
      return JSONValue(13);
    case R.SIM_simsPerBP:
      return JSONValue(2500);
    case R.SIM_parTokensPerSim:
      return JSONValue(1);
    case R.SIM_timeBetweenTokenStarts:
      return JSONValue(0);
    case R.SIM_reuseChosenPaths:
      return JSONValue(true);
    }
  }

  JSONValue root_;
  static bool instantiated_;
  __gshared Cfg instance_;
}

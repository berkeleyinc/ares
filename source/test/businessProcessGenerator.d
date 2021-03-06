module test.businessProcessGenerator;

import proc.businessProcess;

import std.stdio;
import std.random;
import std.conv : text;
import std.algorithm : map, each, min, max;
import std.array : array;
import std.range : empty;

import config;

class BusinessProcessGenerator {
  struct Paradigm {
    enum Type {
      xor,
      and,
      or,
      seq,
      loop
    }

    this(Type t, double p = 0.0) {
      type = t;
      prob = p;
    }

    double prob;
    Type type;
  }

  struct Limits {
    uint maxDepth;
    uint maxFuncs;
  }

  static BusinessProcess generate(in Cfg.PerUser cfg) {
    Paradigm xorPar = Paradigm(Paradigm.Type.xor);
    Paradigm andPar = Paradigm(Paradigm.Type.and);
    Paradigm orPar = Paradigm(Paradigm.Type.or);
    Paradigm seqPar = Paradigm(Paradigm.Type.seq);
    Paradigm loopPar = Paradigm(Paradigm.Type.loop);

    const auto probs = cfg[Cfg.R.GEN_branchTypeProbs].nodeArr!double;
    auto ps = [xorPar, andPar, orPar, seqPar, loopPar];
    foreach (i, ref p; ps)
      p.prob = probs[i];
    const auto branchCountProbs = cfg[Cfg.R.GEN_branchCountProbs].nodeArr!double;
    const auto functionDurationLimits = cfg[Cfg.R.GEN_avgFuncDurs].nodeArr!uint;

    BusinessProcess bp = new BusinessProcess;

    void addEnd(EE from) {
      if (!from.isEvent)
        bp.add([from.id], new Event);
    }

    rndGen = Random(unpredictableSeed);
    EE generate(Limits gc, EE from, uint* pDepth, uint* pFuncs, bool insideAnd = false) {

      size_t n;
      uint depth = 0, funcs = 0;
      if (pDepth == null || pFuncs == null || from is null) {
        pDepth = &depth;
        pFuncs = &funcs;
        Event startEvt = bp.add([], new Event());
        // startEvt.label = "START";
        from = startEvt;
        n = [0, 1, 0, 1, 0].dice;
      } else {
        if (*pFuncs + 1 >= gc.maxFuncs || *pDepth >= gc.maxDepth) {
          // if (typeid(from) == typeid(Function)) { // && typeid(from.deps[0]) != typeid(Gate)) {
          //  writeln("null, pFuncs=", *pFuncs);
          //  return null;
          //}
          n = 3; // force seq
          // } else if (*pFuncs == 0) {
          //   n = 3; // force seq
          //   // TODO
        } else
          n = ps.map!(a => a.prob).dice;
      }
      Paradigm* par = &ps[n];

      // writeln("Choosing " ~ text(par.type) ~ ", prob=", par.prob);
      if (par.type == Paradigm.Type.seq) {
        (*pFuncs)++;
        Function f;
        if (from.isFunc) {
          Event e = bp.add([from.id], new Event);
          f = bp.add([e.id], new Function());
        } else
          f = bp.add([from.id], new Function());
        f.dur = uniform!"[]"(functionDurationLimits[0], functionDurationLimits[1]);
        // Event e = bp.add([f.id], new Event);
        Agent[] ps;

        enum AgentAssignStrategy : size_t {
          newOne = 0,
          useExisting = 1,
          moreThanOne = 2
        }

        AgentAssignStrategy pas = cast(AgentAssignStrategy) dice(50, bp.agts.empty ? 0 : 25, 10);

        final switch (pas) {
        case AgentAssignStrategy.newOne:
          ps ~= bp.add([f.id], new Agent());
          break;
        case AgentAssignStrategy.useExisting:
          ps ~= bp.agts[uniform(0, bp.agts.length)];
          ps[$ - 1].deps ~= [f.id];
          break;
        case AgentAssignStrategy.moreThanOne:
          foreach (i; 0 .. uniform(2, 3))
            ps ~= bp.add([f.id], new Agent());
          break;
        }
        // random Qualifications for each Agent
        // we don't care if p.quals will be empty because during postProcess(), this is fixed
        ps.each!(p => p.quals = bp.funcs.randomSample(uniform!"[]"(0, bp.funcs.length / 2)).map!(a => a.id).array);
        if (*pFuncs >= gc.maxFuncs || *pDepth >= gc.maxDepth) {
          return f;
        } else
          return generate(gc, f, pDepth, pFuncs, insideAnd);
      }

      if (par.type == Paradigm.Type.loop) {
        if (from.isGate && from.asGate.type == Gate.Type.xor) {

          int canSpend = 0;
          immutable int rest = gc.maxFuncs - *pFuncs;
          if (rest > 1)
            canSpend = uniform(0, cast(int)(rest / 1.5));
          return generate(Limits(gc.maxDepth, *pFuncs + canSpend), from, pDepth, pFuncs, insideAnd);
        }
        // if (from.isFunc)
        //   from = bp.add([from.id], new Event);
        EE startConn = bp.add([from.id], new Gate(Gate.Type.xor));
        EE nextConn = bp.add([startConn.id], new Gate(Gate.Type.xor));
        EE line = generate(gc, nextConn, pDepth, pFuncs, insideAnd);
        // if (line.isFunc) {
        //   line = bp.add([line.id], new Event);
        // }
        startConn.deps ~= [line.id];

        // writeln("startConn.id=", startConn.id, ", nextConn.id=", nextConn.id, ", startConn.dep=", line.id);

        // EE startConn = bp.add([from.id], new Gate(Gate.Type.xor));
        // EE line = generate(gc, startConn, pDepth, pFuncs, insideAnd);
        // startConn.deps ~= [line.id];
        return nextConn;
      }

      (*pDepth)++;
      size_t branchCount = dice([0.0, 0.0] ~ branchCountProbs);
      size_t endBranchCount = 0; // dice(50, 50, 5);
      Gate.Type type;
      switch (par.type) {
      case Paradigm.Type.xor:
        type = Gate.Type.xor;
        break;
      case Paradigm.Type.or:
        type = Gate.Type.or;
        break;
      case Paradigm.Type.and:
        type = Gate.Type.and;
        endBranchCount = 0; // can't end branches in AND-blocks

        if (from.isFunc || (from.isGate && from.asGate.type != Gate.Type.and && from.deps.length == 1)) {
          from = bp.add([from.id], new Event);
          //f = bp.add([e.id], new Function());
        }
        break;
      default:
        break;
      }
      // if (insideAnd)
      //   endBranchCount = 0;
      EE startConn = bp.add([from.id], new Gate(type));

      // if (type == Gate.Type.xor) {
      //   foreach (cs; bp.gates) {
      //     if (cs.type == Gate.Type.xor && cs.deps.length > 1 && from.id != cs.id)
      //       cs.deps ~= startConn.id;
      //   }
      // }

      ulong[] branchIds;
      EE[] branches;
      for (int i = 0; i < branchCount; i++) {
        if (i >= 1 && i <= endBranchCount) {
          int canSpend = 0;
          immutable int rest = gc.maxFuncs - *pFuncs;
          if (rest > 1)
            canSpend = uniform(0, rest / 2);
          EE line = startConn;
          if (canSpend > 0) {
            line = generate(Limits(gc.maxDepth, *pFuncs + canSpend), startConn, pDepth, pFuncs,
                insideAnd || type == Gate.Type.and);
          }
          addEnd(line);
        } else {
          auto lastObj = generate(gc, startConn, pDepth, pFuncs, insideAnd);

          if (lastObj.isFunc) {
            lastObj = bp.add([lastObj.id], new Event);
            //f = bp.add([e.id], new Function());
          }
          branches ~= lastObj;
          branchIds ~= lastObj.id;
        }
      }
      EE endConn;
      if (endBranchCount > 0 && branchCount - endBranchCount <= 1) {
        endConn = branches[0];
      } else {
        endConn = bp.add(branchIds, new Gate(type));
        // writeln("adding ENDConn " ~ endConn.name ~ "(" ~ (cast(Gate) endConn)
        //     .symbol ~ "), branchCount: " ~ text(branchCount) ~ ", endBranchCount: " ~ text(endBranchCount));
      }
      (*pDepth)--;

      if (*pFuncs >= gc.maxFuncs || *pDepth >= gc.maxDepth) {
        return endConn;
      } else {
        return generate(gc, endConn, pDepth, pFuncs, insideAnd);
      }
    }

    int maxDepth = cfg[Cfg.R.GEN_maxDepth].as!int;
    int maxFuncs = cfg[Cfg.R.GEN_maxFuncs].as!int;
    auto ee = generate(Limits(maxDepth <= 2 ? 2 : uniform(2, maxDepth), uniform(min(5, maxFuncs - 1), maxFuncs)),
        null, null, null);
    addEnd(ee);

    bp.postProcess();

    return bp;
  }
}

// import pegged.grammar;
//
// import core.stdc.stdlib;
//
// mixin(grammar(`
//   EPC:
//     BP    < Node
//     Node  < Join / Split / Seq
//
//     Join  < 'J ' Act
//     Seq   < 'S ' Act (',' Node)*
//     Split  < 'F ' Act (',' Node)*
//     Act   < Ident ('(' Node+ ')')?
//     Ident < [a-zA-Z][a-zA-Z0-9_]*
// `));
//
// enum input = `S Start`;
// //enum input = `F F1(S F2,F F3(S F4(S F6(S F7(J F8))),S F5),S F8)`;
//
// string worker(ParseTree p) {
//   writeln(p);
//   string parseToCode(ParseTree p) {
//     switch (p.name) {
//     case "EPC":
//     case "EPC.BP":
//       return parseToCode(p.children[0]); // The grammar result has only child: the start rule's parse tree
//     case "EPC.Node":
//     case "EPC.Seq":
//     case "EPC.Act":
//       writeln("name: ", p.name);
//       writefln(" input: %s, begin=%d", p.input, p.begin);
//       foreach (i, m; p.matches)
//         writefln("  match %d: %s", i, m);
//
//       return parseToCode(p.children[0]); // The grammar result has only child: the start rule's parse tree
//     default:
//       return "";
//     }
//   }
//
//   return parseToCode(p);
// }

// string toLaTeX(ParseTree p) {
//   string parseToCode(ParseTree p) {
//     switch (p.name) {
//     case "Wiki":
//       return parseToCode(p.children[0]); // The grammar result has only child: the start rule's parse tree
//     case "Wiki.Document":
//       string result = "\\documentclass{article}\n\\begin{document}\n";
//       foreach (child; p.children) // child is a ParseTree
//         result ~= parseToCode(child);
//       return result ~ "\n\\end{document}\n";
//     case "Wiki.Element":
//       return parseToCode(p.children[0]); // one child only
//     case "Wiki.Section":
//       return "\n\\section{" ~ p.matches[0] // the first match contains the title
//        ~ "}\n";
//     case "Wiki.Subsection":
//       return "\n\\subsection{" ~ p.matches[0] // the first match contains the title
//        ~ "}\n";
//     case "Wiki.Emph":
//       return " \\emph{" ~ p.matches[0] // the first match contains the text to emphasize
//        ~ "} ";
//     case "Wiki.List":
//       string result = "\n\\begin{itemize}\n";
//       foreach (child; p.children)
//         result ~= parseToCode(child);
//       return result ~ "\\end{itemize}\n";
//     case "Wiki.ListElement":
//       return "\\item " ~ p.matches[0] ~ "\n";
//     case "Wiki.Text":
//       return p.matches[0];
//     default:
//       return "";
//     }
//   }
//
//   return parseToCode(p);
// }

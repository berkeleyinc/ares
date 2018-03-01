module graphviz.dotGenerator;

import proc.process;

import std.stdio;
import std.random;
import std.conv : text;
import std.file : write;

import core.stdc.stdlib;

struct DotGeneratorOptions {
  bool showParts = false;
}

@trusted string generateDot(const Process bp, const DotGeneratorOptions opt = DotGeneratorOptions()) {
  string dot;
  scope (exit) {
    write("/tmp/graph.dot", dot);
  }

  auto fw = delegate(string str, string* pdot = null) {
    if (pdot == null)
      pdot = &dot;
    *pdot ~= str ~ '\n';
  };
  dot ~= "digraph G {\n";
  dot ~= "graph[splines = \"spline\", nodesep = \"0.5\"];\n";
  dot ~= "rankdir = \"LR\";\n";
  string dir, undir;
  foreach (bo; bp.bos) {
    if (!opt.showParts && bo.isPart)
      continue;
    foreach (depID; bo.deps) {
      if (bo.isPart) 
        fw(bp.bos[depID].name ~ " -> " ~ bo.name ~ " [constraint=true]", &undir);
      else
        fw(bp.bos[depID].name ~ " -> " ~ bo.name, &dir);
    }
  }
  dot ~= `node[shape = "box", style = "rounded,filled", fillcolor = "#cedeef:#ffffff", gradientangle = 270, color = "#5a677b",
                 width = "0.5", fontcolor = "#5a677b", fontname = "sans-serif", fontsize = "14.0", penwidth = 1];
`;
  foreach (f; bp.funcs)
    dot ~= f.name ~ /*(f.label.length > 0 ? "[label=\"" ~ f.label ~ "\", weight=1]" : "") ~*/ ";\n";
  dot ~= `node[shape = "hexagon", style = "filled", fillcolor = "#ce7777:#ffffff", gradientangle = 270, color = "#5a677b",
                 width = "0.5", fontcolor = "#5a677b", fontname = "sans-serif", fontsize = "14.0", penwidth = 1];
`;
  foreach (e; bp.evts) {
    dot ~= e.name ~ /*(e.label.length > 0 ? "[label=\"" ~ e.label ~ "\", weight=1]" : "") ~*/ ";\n";
  }
  dot ~= `node[shape = "circle",
                 fixedsize="true",
                 width = "0.5", height = "0.5", fontsize = 20, style = "filled", fillcolor = "#ffff84:#ffffbd",
                 gradientangle = 270, color = "#a6a855", fontcolor = "#708041", fontname = "sans-serif"];
`;
  foreach (c; bp.cnns) {
    dot ~= c.name ~ " [label=\"" ~ c.symbol ~ "\", weight=1];\n";
  }
  if (opt.showParts) {
    dot ~= `node[shape = "circle",
                 width = "0.5", fontsize = "14.0", penwidth = 1, style = "filled", fillcolor = "#aaff84:#aaffbd",
                 gradientangle = 270, color = "#77a855", fontcolor = "#708041", fontname = "sans-serif"];
`;
    foreach (p; bp.parts) {
      dot ~= p.name ~ " [weight=0.1];\n";
    }
  }
  dot ~= "edge[color = \"#5a677b\"];\n";
  dot ~= "{edge[dir=none];\n";
  dot ~= undir ~ "}\n";
  dot ~= dir;
  dot ~= "}";
  return dot;
}

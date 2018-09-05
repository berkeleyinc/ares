module graphviz.dotGenerator;

import proc.businessProcess;

import std.stdio;
import std.random;
import std.conv : text;
import std.file : write;

import core.stdc.stdlib;

struct DotGeneratorOptions {
  bool showAgents = true;
}

@trusted string generateDot(const BusinessProcess bp, const DotGeneratorOptions opt = DotGeneratorOptions()) {
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
  foreach (ee; bp.epcElements) {
    if (!opt.showAgents && ee.isAgent)
      continue;
    foreach (depID; ee.deps) {
      if (ee.isAgent) 
        fw(bp.epcElements[depID].name ~ " -> " ~ ee.name ~ " [constraint=true]", &undir);
      else
        fw(bp.epcElements[depID].name ~ " -> " ~ ee.name ~ " [style=\"dashed\"]", &dir);
    }
  }
  // fillcolor = "#cedeef:#ffffff"
  dot ~= `node[shape = "box", style = "rounded,filled", fillcolor = "#66ff66:#ffffff", gradientangle = 270, color = "#5a677b",
                 width = "0.5", fontcolor = "#5a677b", fontname = "sans-serif", fontsize = "14.0", penwidth = 1];
`;
  foreach (f; bp.funcs)
    dot ~= f.name ~ /*(f.label.length > 0 ? "[label=\"" ~ f.label ~ "\", weight=1]" : "") ~*/ ";\n";
  // fillcolor = "#ce7777:#ffffff"
  dot ~= `node[shape = "hexagon", style = "filled", fillcolor = "#ff6666:#ffffff", gradientangle = 270, color = "#5a677b",
                 width = "0.5", fontcolor = "#5a677b", fontname = "sans-serif", fontsize = "14.0", penwidth = 1];
`;
  foreach (e; bp.evts) {
    dot ~= e.name ~ /*(e.label.length > 0 ? "[label=\"" ~ e.label ~ "\", weight=1]" : "") ~*/ ";\n";
  }
  // fillcolor = "#ffff84:#ffffbd"
  dot ~= `node[shape = "circle",
                 fixedsize="true",
                 width = "0.5", height = "0.5", fontsize = 20, style = "filled", fillcolor = "#999999:#ffffff",
                 gradientangle = 270, color = "#5a677b", fontcolor = "#5a677b", fontname = "sans-serif"];
`;
  foreach (c; bp.gates) {
    dot ~= c.name ~ " [label=\"" ~ c.symbol ~ "\", weight=1];\n";
  }
  if (opt.showAgents) {
    // fillcolor = "#aaff84:#aaffbd"
    dot ~= `node[shape = "Mcircle",
                 width = "0.5", fontsize = "14.0", penwidth = 1, style = "filled", fillcolor = "#ffff66:#ffffff",
                 gradientangle = 270, color = "#5a677b", fontcolor = "#5a677b", fontname = "sans-serif"];
`;
    foreach (p; bp.agts) {
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

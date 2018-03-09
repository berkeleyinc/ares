module util;

import std.stdio, std.range;
public import std.algorithm;
// public import pprint.pp;
public import opmix.dup;
public import vibe.core.log;

T[][] comb(T)(T[] s, in size_t m) pure nothrow @safe {
  if (!m)
    return [[]];
  if (s.empty)
    return [];
  return s[1 .. $].comb(m - 1).map!(x => s[0] ~ x).array ~ s[1 .. $].comb(m);
}

// version (DigitalMars) {
// } else {
//   import std.traits;
//   T mean(T = double, R)(R r) if (isInputRange!R && isNumeric!(ElementType!R) && !isInfinite!R) {
//     if (r.empty)
//       return T.init;
// 
//     Unqual!T meanRes = 0;
//     size_t i = 1;
// 
//     // Knuth & Welford mean calculation
//     // division per element is slower, but more accurate
//     for (; !r.empty; r.popFront()) {
//       T delta = r.front - meanRes;
//       meanRes += delta / i++;
//     }
// 
//     return meanRes;
//   }
// }

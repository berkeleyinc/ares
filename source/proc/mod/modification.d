module proc.mod.modification;

import proc.process;

import std.range;
import std.algorithm;
import std.typecons;

interface Modification {
  void apply(Process p);
  @property string toString();
}



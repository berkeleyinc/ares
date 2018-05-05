module proc.mod.modification;

import proc.businessProcess;

import std.range;
import std.algorithm;
import std.typecons;

interface Modification {
  void apply(BusinessProcess p);
  @property string toString();
}



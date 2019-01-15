module proc.epcElement;

import std.ascii : isUpper;
import std.conv : text;

import msgpack : nonPacked;

class EE {
  ulong id;

  @property string name() const {
    string ret;
    foreach (c; typeid(this).name)
      if (c.isUpper)
        ret ~= c;
    return ret ~ text(id);
  }

  ulong[] deps; // predecessor node IDs
  @nonPacked ulong[] succs; // successor node IDs (generated through BusinessProcess.postProcess)
}

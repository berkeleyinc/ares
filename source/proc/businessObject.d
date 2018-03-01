module proc.businessObject;

import std.ascii : isUpper;
import std.conv : text;

import msgpack : nonPacked;

class BO {
  ulong id;

  @property string name() const {
    string ret;
    foreach (c; typeid(this).name)
      if (c.isUpper)
        ret ~= c;
    return ret ~ text(id);
  }

  //   @property string label() const {
  //     return label_;
  //   }
  // 
  //   @property void label(string n) {
  //     label_ = n;
  //   }

  ulong[] deps;
  @nonPacked ulong[] succs;
private:
  //  string label_;
}

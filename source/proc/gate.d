module proc.gate;

import proc.businessObject;

import std.typecons;
import msgpack : nonPacked;

bool isGate(const BO bo) {
  return typeid(bo) == typeid(Gate);
}

Gate asGate(BO bo) {
  return cast(Gate) bo;
}

const(Gate) asGate(const BO bo) {
  return cast(Gate) bo;
}

class Gate : BO {
  this(Type type = Type.and) {
    this.type = type;
  }

  enum Type {
    and,
    or,
    xor,
  };
  Type type;
  @property string symbol() const {
    string label;
    final switch (type) {
    case Gate.Type.and:
      return "∧";
    case Gate.Type.or:
      return "∨";
    case Gate.Type.xor:
      return "X";
    }
  }

  // probability that a certain branch will be chosen by the simulator
  Tuple!(ulong, "boID", double, "prob")[] probs;

  @nonPacked Nullable!ulong partner;
  @nonPacked ulong[] loopsFor = [];
}

module proc.gate;

import proc.epcElement;

import std.typecons;
import msgpack : nonPacked;

bool isGate(const EE ee) {
  return typeid(ee) == typeid(Gate);
}

Gate asGate(EE ee) {
  return cast(Gate) ee;
}

const(Gate) asGate(const EE ee) {
  return cast(Gate) ee;
}

class Gate : EE {
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
      return "⊻";
    }
  }

  // probability that a certain branch will be chosen by the simulator
  Tuple!(ulong, "eeID", double, "prob")[] probs;

  @nonPacked Nullable!ulong partner;
  @nonPacked ulong[] loopsFor = [];
}

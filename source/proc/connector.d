module proc.connector;

import proc.businessObject;

import std.typecons;
import msgpack : nonPacked;

bool isConn(const BO bo) {
  return typeid(bo) == typeid(Connector);
}

Connector asConn(BO bo) {
  return cast(Connector) bo;
}

const(Connector) asConn(const BO bo) {
  return cast(Connector) bo;
}

class Connector : BO {
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
    case Connector.Type.and:
      return "∧";
    case Connector.Type.or:
      return "∨";
    case Connector.Type.xor:
      return "X";
    }
  }

  // probability that a certain branch will be chosen by the simulator
  Tuple!(ulong, "boId", double, "prob")[] probs;

  @nonPacked Nullable!ulong partner;
  @nonPacked ulong[] loopsFor = [];
}

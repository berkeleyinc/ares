module proc.func;

import proc.epcElement;
import msgpack;

bool isFunc(const EE ee) {
  return typeid(ee) == typeid(Function);
}

Function asFunc(EE ee) {
  return cast(Function) ee;
}

const(Function) asFunc(const EE ee) {
  return cast(const Function) ee;
}

class Function : EE {
  ulong dur = 1; // average duration
  // bool opt = false; // optional, will only discard as a last matter
  ulong[] dependsOn; // Functions that have to run before

  @nonPacked ulong[] agts; // All Agents that are assigned to this Function
}

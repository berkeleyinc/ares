module proc.func;

import proc.businessObject;
import msgpack;

bool isFunc(const BO bo) {
  return typeid(bo) == typeid(Function);
}

Function asFunc(BO bo) {
  return cast(Function) bo;
}

const(Function) asFunc(const BO bo) {
  return cast(const Function) bo;
}

class Function : BO {
  ulong dur = 1; // average duration
  // bool opt = false; // optional, will only discard as a last matter
  ulong[] dependsOn; // Functions that have to run before

  @nonPacked ulong[] ress; // All Resources that are assigned to this Function
}

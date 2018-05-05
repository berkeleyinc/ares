module proc.resource;

import proc.epcElement;

bool isRes(const EE ee) {
  return typeid(ee) == typeid(Resource);
}

Resource asRes(EE ee) {
  return cast(Resource) ee;
}

const(Resource) asRes(const EE ee) {
  return cast(const(Resource)) ee;
}

class Resource : EE
{
    ulong[] quals = [];
}

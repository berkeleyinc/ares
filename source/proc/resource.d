module proc.resource;

import proc.businessObject;

bool isRes(const BO bo) {
  return typeid(bo) == typeid(Resource);
}

Resource asRes(BO bo) {
  return cast(Resource) bo;
}

const(Resource) asRes(const BO bo) {
  return cast(const(Resource)) bo;
}

class Resource : BO
{
    ulong[] quals = [];
}

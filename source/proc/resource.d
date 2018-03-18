module proc.resource;

import proc.businessObject;

bool isRes(const BO bo) {
  return typeid(bo) == typeid(Participant);
}

Participant asRes(BO bo) {
  return cast(Participant) bo;
}

const(Participant) asRes(const BO bo) {
  return cast(const(Participant)) bo;
}

class Participant : BO
{
    ulong[] quals = [];
}

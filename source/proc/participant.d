module proc.participant;

import proc.businessObject;

bool isPart(const BO bo) {
  return typeid(bo) == typeid(Participant);
}

Participant asPart(BO bo) {
  return cast(Participant) bo;
}

const(Participant) asPart(const BO bo) {
  return cast(const(Participant)) bo;
}

class Participant : BO
{
    ulong[] quals = [];
}

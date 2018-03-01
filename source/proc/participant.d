module proc.participant;

import proc.businessObject;

bool isPart(const BO bo) {
  return typeid(bo) == typeid(Participant);
}

Participant asPart(BO bo) {
  return cast(Participant) bo;
}

class Participant : BO
{
    ulong[] quals = [];
}

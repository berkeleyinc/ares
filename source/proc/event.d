module proc.event;

import proc.businessObject;

bool isEvent(const BO bo) {
  return typeid(bo) == typeid(Event);
}

Event asEvent(BO bo) {
  return cast(Event) bo;
}

const(Event) asEvent(const BO bo) {
  return cast(const Event) bo;
}

class Event : BO {
}

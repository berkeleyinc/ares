module proc.event;

import proc.epcElement;

bool isEvent(const EE ee) {
  return typeid(ee) == typeid(Event);
}

Event asEvent(EE ee) {
  return cast(Event) ee;
}

const(Event) asEvent(const EE ee) {
  return cast(const Event) ee;
}

class Event : EE {
}

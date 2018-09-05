module proc.agent;

import proc.epcElement;

bool isAgent(const EE ee) {
  return typeid(ee) == typeid(Agent);
}

Agent asAgent(EE ee) {
  return cast(Agent) ee;
}

const(Agent) asAgent(const EE ee) {
  return cast(const(Agent)) ee;
}

class Agent : EE
{
    ulong[] quals = [];
}

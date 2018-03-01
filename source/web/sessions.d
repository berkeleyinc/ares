module web.sessions;

import proc.process;
import config;

class Sessions {
public:
  static class Session {
    this() {
      bps = [];
      cfg = Cfg.get().new Cfg.PerUser;
    }
    Process[] bps;
    Cfg.PerUser cfg;
  }

  private this() {
  }

  static bool exists(string sessionID) {
    return !(sessionID !in inst.sessions_);
  }

  static Session get(string sessionID) {
    return inst.sessions_[sessionID];
  }

  static void create(string sessionID) {
    inst.sessions_[sessionID] = new Session;
  }

  static @property size_t sessionCount() {
    return inst.sessions_.length;
  }
  static void terminateSessions() {
    inst.sessions_.clear();
  }

private:
  // Cache instantiation flag in thread-local bool
  // Thread local
  private static bool instantiated_;
  // Thread global
  private __gshared Sessions instance_;

  Session[string] sessions_;


  static @property Sessions inst() {
    if (!instantiated_) {
      synchronized (Sessions.classinfo) {
        if (!instance_) {
          instance_ = new Sessions();
        }

        instantiated_ = true;
      }
    }
    return instance_;
  }
}

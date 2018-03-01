module web.rest;

interface IRestAPI {
@safe:
  // Matches "GET /data"
  @property string data();
  // Matches "PUT /data"
  @property void data(string info);
  // Matches "POST /sum"
  // or "GET /sum?a=...&b=..."
  int postSum(int a, int b);
}

class Rest : IRestAPI {
override:
@safe:
  @property string data() {
    return "dot";
  }

  @property void data(string v) {
    // _data = v;
  }

  int postSum(int a, int b) {
    return a + b;
  }
}

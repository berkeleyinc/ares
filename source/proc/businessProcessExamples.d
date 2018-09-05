module proc.businessProcessExamples;

import proc.businessProcess;


BusinessProcess dilemmaExample() {
  BusinessProcess p = new BusinessProcess;
  auto e = p.add([], new Event);
  auto Z = p.add([e.id], new Function);
  p.add([Z.id], new Agent);
  auto c0 = p.add([Z.id], new Gate(Gate.Type.xor));

  auto B = p.add([c0.id], new Function);
  p.add([B.id], new Agent);
  auto c1 = p.add([B.id], new Gate(Gate.Type.xor));
  auto L = p.add([c0.id, c1.id], new Function);
  p.add([L.id], new Agent);

  e = p.add([L.id, c1.id], new Event);
  p.postProcess();
  return p;
}

BusinessProcess assignAgentExample(bool assign = false) {
  BusinessProcess p = new BusinessProcess;
  auto e0 = p.add([], new Event);
  auto f1 = p.add([e0.id], new Function);
  p.add([f1.id], new Agent);
  auto c3 = p.add([f1.id], new Gate(Gate.Type.and));

  EE f06 = null;
  auto e04 = p.add([c3.id], new Event);
  f06 = p.add([e04.id], new Function);
  auto p07 = p.add([f06.id], new Agent);
  auto e4 = p.add([f06.id], new Event);
  auto f6 = p.add([e4.id], new Function);
  auto p7 = p.add([f6.id], new Agent);
  with (p.add([f6.id], new Agent))
    quals ~= f1.id;
  with (p.add([f6.id], new Agent))
    quals ~= f06.id;

  auto e5 = p.add([c3.id], new Event);
  auto f8 = p.add([e5.id], new Function);

  p.add([f8.id], new Agent);
  with (p.add([f6.id], new Agent))
    quals ~= f8.id;

  auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.and));
  auto e11 = p.add([c10.id], new Event);
  // auto f12 = p.add([e11.id], new Function);
  // p7.asAgent.quals ~= f12.id;
  // p.add([f12.id], new Agent);
  // // auto e13 = p.add([f12.id], new Event);
  // auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
  // auto e15 = p.add([c14.id], new Event);
  // auto f16 = p.add([e15.id], new Function);
  // p.add([f16.id], new Agent);
  // c10.deps ~= f16.id;
  // auto e18 = p.add([c14.id], new Event);
  p.postProcess();

  return p;
}

BusinessProcess discardFunctionExample(bool discard = false) {
  BusinessProcess p = new BusinessProcess;
  auto e0 = p.add([], new Event);
  auto f1 = p.add([e0.id], new Function);
  p.add([f1.id], new Agent);
  auto c3 = p.add([f1.id], new Gate(Gate.Type.and));

  EE f06 = null;
  if (!discard) {
    auto e04 = p.add([c3.id], new Event);
    f06 = p.add([e04.id], new Function);
    auto p07 = p.add([f06.id], new Agent);
  }
  auto e4 = p.add([f06 is null ? c3.id : f06.id], new Event);
  auto f6 = p.add([e4.id], new Function);
  auto p7 = p.add([f6.id], new Agent);

  auto e5 = p.add([c3.id], new Event);
  auto f8 = p.add([e5.id], new Function);

  p.add([f8.id], new Agent);

  auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.and));
  auto e11 = p.add([c10.id], new Event);
  // auto f12 = p.add([e11.id], new Function);
  // p7.asAgent.quals ~= f12.id;
  // p.add([f12.id], new Agent);
  // // auto e13 = p.add([f12.id], new Event);
  // auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
  // auto e15 = p.add([c14.id], new Event);
  // auto f16 = p.add([e15.id], new Function);
  // p.add([f16.id], new Agent);
  // c10.deps ~= f16.id;
  // auto e18 = p.add([c14.id], new Event);
  p.postProcess();

  return p;
}

BusinessProcess xorLoopExample() {
  BusinessProcess p = new BusinessProcess;
  auto e0 = p.add([], new Event);
  auto f1 = p.add([e0.id], new Function);
  p.add([f1.id], new Agent);
  auto c3 = p.add([f1.id], new Gate(Gate.Type.xor));
  auto e4 = p.add([c3.id], new Event);
  auto e5 = p.add([c3.id], new Event);
  auto f6 = p.add([e4.id], new Function);
  auto p7 = p.add([f6.id], new Agent);
  auto f8 = p.add([e5.id], new Function);
  p.add([f8.id], new Agent);
  auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.xor));
  auto e11 = p.add([c10.id], new Event);
  auto f12 = p.add([e11.id], new Function);
  p7.asAgent.quals ~= f12.id;
  p.add([f12.id], new Agent);
  // auto e13 = p.add([f12.id], new Event);
  auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
  auto e15 = p.add([c14.id], new Event);
  auto f16 = p.add([e15.id], new Function);
  p.add([f16.id], new Agent);
  c10.deps ~= f16.id;
  auto e18 = p.add([c14.id], new Event);
  p.postProcess();
  return p;
}

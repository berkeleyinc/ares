module proc.businessProcessExamples;

import proc.businessProcess;

BusinessProcess assignResourceExample(bool assign = false) {
  BusinessProcess p = new BusinessProcess;
  auto e0 = p.add([], new Event);
  auto f1 = p.add([e0.id], new Function);
  p.add([f1.id], new Resource);
  auto c3 = p.add([f1.id], new Gate(Gate.Type.and));

  EE f06 = null;
  auto e04 = p.add([c3.id], new Event);
  f06 = p.add([e04.id], new Function);
  auto p07 = p.add([f06.id], new Resource);
  auto e4 = p.add([f06.id], new Event);
  auto f6 = p.add([e4.id], new Function);
  auto p7 = p.add([f6.id], new Resource);
  with (p.add([f6.id], new Resource))
    quals ~= f1.id;
  with (p.add([f6.id], new Resource))
    quals ~= f06.id;

  auto e5 = p.add([c3.id], new Event);
  auto f8 = p.add([e5.id], new Function);

  p.add([f8.id], new Resource);
  with (p.add([f6.id], new Resource))
    quals ~= f8.id;

  auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.and));
  auto e11 = p.add([c10.id], new Event);
  // auto f12 = p.add([e11.id], new Function);
  // p7.asRes.quals ~= f12.id;
  // p.add([f12.id], new Resource);
  // // auto e13 = p.add([f12.id], new Event);
  // auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
  // auto e15 = p.add([c14.id], new Event);
  // auto f16 = p.add([e15.id], new Function);
  // p.add([f16.id], new Resource);
  // c10.deps ~= f16.id;
  // auto e18 = p.add([c14.id], new Event);
  p.postProcess();

  return p;
}

BusinessProcess discardFunctionExample(bool discard = false) {
  BusinessProcess p = new BusinessProcess;
  auto e0 = p.add([], new Event);
  auto f1 = p.add([e0.id], new Function);
  p.add([f1.id], new Resource);
  auto c3 = p.add([f1.id], new Gate(Gate.Type.and));

  EE f06 = null;
  if (!discard) {
    auto e04 = p.add([c3.id], new Event);
    f06 = p.add([e04.id], new Function);
    auto p07 = p.add([f06.id], new Resource);
  }
  auto e4 = p.add([f06 is null ? c3.id : f06.id], new Event);
  auto f6 = p.add([e4.id], new Function);
  auto p7 = p.add([f6.id], new Resource);

  auto e5 = p.add([c3.id], new Event);
  auto f8 = p.add([e5.id], new Function);

  p.add([f8.id], new Resource);

  auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.and));
  auto e11 = p.add([c10.id], new Event);
  // auto f12 = p.add([e11.id], new Function);
  // p7.asRes.quals ~= f12.id;
  // p.add([f12.id], new Resource);
  // // auto e13 = p.add([f12.id], new Event);
  // auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
  // auto e15 = p.add([c14.id], new Event);
  // auto f16 = p.add([e15.id], new Function);
  // p.add([f16.id], new Resource);
  // c10.deps ~= f16.id;
  // auto e18 = p.add([c14.id], new Event);
  p.postProcess();

  return p;
}

BusinessProcess xorLoopExample() {
  BusinessProcess p = new BusinessProcess;
  auto e0 = p.add([], new Event);
  auto f1 = p.add([e0.id], new Function);
  p.add([f1.id], new Resource);
  auto c3 = p.add([f1.id], new Gate(Gate.Type.xor));
  auto e4 = p.add([c3.id], new Event);
  auto e5 = p.add([c3.id], new Event);
  auto f6 = p.add([e4.id], new Function);
  auto p7 = p.add([f6.id], new Resource);
  auto f8 = p.add([e5.id], new Function);
  p.add([f8.id], new Resource);
  auto c10 = p.add([f6.id, f8.id], new Gate(Gate.Type.xor));
  auto e11 = p.add([c10.id], new Event);
  auto f12 = p.add([e11.id], new Function);
  p7.asRes.quals ~= f12.id;
  p.add([f12.id], new Resource);
  // auto e13 = p.add([f12.id], new Event);
  auto c14 = p.add([f12.id], new Gate(Gate.Type.xor));
  auto e15 = p.add([c14.id], new Event);
  auto f16 = p.add([e15.id], new Function);
  p.add([f16.id], new Resource);
  c10.deps ~= f16.id;
  auto e18 = p.add([c14.id], new Event);
  p.postProcess();
  return p;
}

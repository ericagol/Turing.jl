# Test Trace

using Turing
using Distributions

import Turing: Trace, Trace, current_trace, fork, VarName, Sampler

global n = 0

alg = PG(5, 1)
spl = Turing.Sampler(alg)
dist = Normal(0, 1)

function f2()
  global n
  t = TArray(Int, 1);
  t[1] = 0;
  while true
    ct = current_trace()
    vn = VarName(gensym(), :x, "[$n]", 1)
    Turing.assume(spl, dist, vn, ct.vi); n += 1;
    produce(t[1]);
    vn = VarName(gensym(), :x, "[$n]", 1)
    Turing.assume(spl, dist, vn, ct.vi); n += 1;
    t[1] = 1 + t[1]
  end
end

# Test task copy version of trace
t = Trace(f2)

consume(t); consume(t)
a = fork(t);
consume(a); consume(a)

Base.@assert consume(t) == 2
Base.@assert consume(a) == 4

doc"""
    PG(n_particles::Int, n_iters::Int)

Particle Gibbs sampler.

Usage:

```julia
PG(100, 100)
```

Example:

```julia
# Define a simple Normal model with unknown mean and variance.
@model gdemo(x) = begin
  s ~ InverseGamma(2,3)
  m ~ Normal(0,sqrt.(s))
  x[1] ~ Normal(m, sqrt.(s))
  x[2] ~ Normal(m, sqrt.(s))
  return s, m
end

sample(gdemo([1.5, 2]), PG(100, 100))
```
"""
immutable PG <: InferenceAlgorithm
  n_particles           ::    Int         # number of particles used
  n_iters               ::    Int         # number of iterations
  resampler             ::    Function    # function to resample
  space                 ::    Set         # sampling space, emtpy means all
  gid                   ::    Int         # group ID
  PG(n1::Int, n2::Int) = new(n1, n2, resampleSystematic, Set(), 0)
  PG(n1::Int, n2::Int, resampler::Function, space::Set, gid::Int) = new(n1, n2, resampler, space, gid)
  function PG(n1::Int, n2::Int, space...)
    space = isa(space, Symbol) ? Set([space]) : Set(space)
    new(n1, n2, resampleSystematic, space, 0)
  end
  PG(alg::PG, new_gid::Int) = new(alg.n_particles, alg.n_iters, alg.resampler, alg.space, new_gid)
end

const CSMC = PG # type alias of PG as Conditional SMC

Sampler(alg::PG) = begin
  info = Dict{Symbol, Any}()
  info[:logevidence] = []
  Sampler(alg, info)
end

step(model::Function, spl::Sampler{PG}, vi::VarInfo, _::Bool) = step(model, spl, vi)

step(model::Function, spl::Sampler{PG}, vi::VarInfo) = begin
  particles = ParticleContainer{Trace}(model)

  vi.num_produce = 0;  # Reset num_produce before new sweep\.
  ref_particle = isempty(vi) ?
                 nothing :
                 forkr(Trace(model, spl, vi))
  
  set_retained_vns_del_by_spl!(vi, spl)
  resetlogp!(vi)

  if ref_particle == nothing
    push!(particles, spl.alg.n_particles, spl, vi)
  else
    push!(particles, spl.alg.n_particles-1, spl, vi)
    push!(particles, ref_particle)
  end

  while consume(particles) != Val{:done}
    # TODO: fork somehow cause ProgressMeter to broke - need to figure out why
    resample!(particles, spl.alg.resampler, ref_particle)
  end

  ## pick a particle to be retained.
  Ws, _ = weights(particles)
  indx = randcat(Ws)
  push!(spl.info[:logevidence], particles.logE)

  particles[indx].vi
end

sample(model::Function, alg::PG;
       save_state=false,         # flag for state saving
       resume_from=nothing,      # chain to continue
       reuse_spl_n=0             # flag for spl re-using
      ) = begin

  spl = reuse_spl_n > 0 ?
        resume_from.info[:spl] :
        Sampler(alg)

  @assert typeof(spl.alg) == typeof(alg) "[Turing] alg type mismatch; please use resume() to re-use spl"

  n = reuse_spl_n > 0 ?
      reuse_spl_n :
      alg.n_iters
  samples = Vector{Sample}()

  ## custom resampling function for pgibbs
  ## re-inserts reteined particle after each resampling step
  time_total = zero(Float64)

  vi = resume_from == nothing ?
       VarInfo() :
       resume_from.info[:vi]

  pm = nothing
  if PROGRESS spl.info[:progress] = ProgressMeter.Progress(n, 1, "[PG] Sampling...", 0) end

  for i = 1:n
    time_elapsed = @elapsed vi = step(model, spl, vi)
    push!(samples, Sample(vi))
    samples[i].value[:elapsed] = time_elapsed

    time_total += time_elapsed

    if PROGRESS  && spl.alg.gid == 0
      ProgressMeter.next!(spl.info[:progress])
    end
  end

  println("[PG] Finished with")
  println("  Running time    = $time_total;")

  loge = exp.(mean(spl.info[:logevidence]))
  if resume_from != nothing   # concat samples
    unshift!(samples, resume_from.value2...)
    pre_loge = resume_from.weight
    # Calculate new log-evidence
    pre_n = length(resume_from.value2)
    loge = exp.((log(pre_loge) * pre_n + log(loge) * n) / (pre_n + n))
  end
  c = Chain(loge, samples)       # wrap the result by Chain

  if save_state               # save state
    save!(c, spl, model, vi)
  end

  c
end

assume{T<:Union{PG,SMC}}(spl::Sampler{T}, dist::Distribution, vn::VarName, _::VarInfo) = begin
  vi = current_trace().vi
  if isempty(spl.alg.space) || vn.sym in spl.alg.space
    if ~haskey(vi, vn)
      r = rand(dist)
      push!(vi, vn, r, dist, spl.alg.gid)
      spl.info[:cache_updated] = CACHERESET # sanity flag mask for getidcs and getranges
    elseif is_flagged(vi, vn, "del")
      unset_flag!(vi, vn, "del")
      r = rand(dist)
      vi[vn] = vectorize(dist, r)
      setgid!(vi, spl.alg.gid, vn)
      setorder!(vi, vn, vi.num_produce)
    else
      updategid!(vi, vn, spl)
      r = vi[vn]
    end
  else # vn belongs to other sampler <=> conditionning on vn
    if haskey(vi, vn)
      r = vi[vn]
    else
      r = rand(dist)
      push!(vi, vn, r, dist, -1)
    end
    acclogp!(vi, logpdf_with_trans(dist, r, istrans(vi, vn)))
  end
  r, zero(Real)
end

assume{A<:Union{PG,SMC},D<:Distribution}(spl::Sampler{A}, dists::Vector{D}, vn::VarName, var::Any, vi::VarInfo) =
  error("[Turing] PG and SMC doesn't support vectorizing assume statement")

observe{T<:Union{PG,SMC}}(spl::Sampler{T}, dist::Distribution, value, vi) = begin
  produce(logpdf(dist, value))
  zero(Real)
end

observe{A<:Union{PG,SMC},D<:Distribution}(spl::Sampler{A}, ds::Vector{D}, value::Any, vi::VarInfo) =
  error("[Turing] PG and SMC doesn't support vectorizing observe statement")

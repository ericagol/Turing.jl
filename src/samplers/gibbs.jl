immutable Gibbs <: InferenceAlgorithm
  n_iters   ::  Int     # number of Gibbs iterations
  algs      ::  Tuple   # component sampling algorithms
  thin      ::  Bool    # if thinning to output only after a whole Gibbs sweep
  gid       ::  Int
  Gibbs(n_iters::Int, algs...; thin=true) = new(n_iters, algs, thin, 0)
  Gibbs(alg::Gibbs, new_gid) = new(alg.n_iters, alg.algs, alg.thin, new_gid)
end

typealias GibbsComponent Union{Hamiltonian,PG}

function Sampler(alg::Gibbs)
  n_samplers = length(alg.algs)
  samplers = Array{Sampler}(n_samplers)

  space = Set{Symbol}()

  for i in 1:n_samplers
    sub_alg = alg.algs[i]
    if isa(sub_alg, GibbsComponent)
      samplers[i] = Sampler(typeof(sub_alg)(sub_alg, i))
    else
      error("[GibbsSampler] unsupport base sampling algorithm $alg")
    end
    space = union(space, sub_alg.space)
  end

  # Sanity check for space
  @assert issubset(Turing._compiler_[:pvars], space) "[GibbsSampler] symbols specified to samplers ($space) doesn't cover the model parameters ($(Turing._compiler_[:pvars]))"

  if Turing._compiler_[:pvars] != space
    warn("[GibbsSampler] extra parameters specified by samplers don't exist in model: $(setdiff(space, Turing._compiler_[:pvars]))")
  end

  info = Dict{Symbol, Any}()
  info[:samplers] = samplers

  Sampler(alg, info)
end

function sample(model::Function, alg::Gibbs)
  spl = Sampler(alg)  # init the (master) Gibbs sampler

  # Initialize samples
  sub_sample_n = []
  for sub_alg in alg.algs
    if isa(sub_alg, GibbsComponent)
      push!(sub_sample_n, sub_alg.n_iters)
    else
      error("[GibbsSampler] unsupport base sampling algorithm $alg")
    end
  end

  # Compute the number of samples to store
  sample_n = alg.n_iters * (alg.thin ? 1 : sum(sub_sample_n))

  # Init samples
  samples = Array{Sample}(sample_n)
  weight = 1 / sample_n
  for i = 1:sample_n
    samples[i] = Sample(weight, Dict{Symbol, Any}())
  end

  # Init parameters
  varInfo = model()
  ref_particle = nothing
  i_thin = 1

  n = spl.alg.n_iters

  # Gibbs steps
  spl.info[:progress] = ProgressMeter.Progress(n, 1, "[Gibbs] Sampling...", 0)
  for i = 1:n
    dprintln(2, "Gibbs stepping...")

    for local_spl in spl.info[:samplers]
      local_spl.info[:progress] = spl.info[:progress]
      # dprintln(2, "Sampler stepping...")
      dprintln(2, "$(typeof(local_spl)) stepping...")
      # println(varInfo)
      if isa(local_spl.alg, Hamiltonian)

        for _ = 1:local_spl.alg.n_iters
          dprintln(2, "recording old θ...")
          old_vi = deepcopy(varInfo)
          is_accept, varInfo = step(model, local_spl, varInfo, i==1)
          if ~is_accept
            # NOTE: this might cause problem if new variables is added to VarInfo,
            #    which will add new elements to vi.idcs etc.
            varInfo = old_vi
          end
          if ~spl.alg.thin
            samples[i_thin].value = Sample(varInfo).value
            i_thin += 1
          end
        end
      elseif isa(local_spl.alg, PG)
        # Update new VarInfo to the reference particle
        varInfo.index = 0
        varInfo.num_produce = 0
        if ref_particle != nothing
          ref_particle.vi = varInfo
        end
        # Clean variables belonging to the current sampler
        varInfo = deepcopy(varInfo)
        varInfo[getretain(varInfo, 0, local_spl)] = NULL
        # Local samples
        for _ = 1:local_spl.alg.n_iters
          ref_particle, _ = step(model, local_spl, varInfo, ref_particle)
          if ~spl.alg.thin
            samples[i_thin].value = Sample(ref_particle.vi).value
            i_thin += 1
          end
        end
        varInfo = ref_particle.vi
      else
        error("[GibbsSampler] unsupport base sampler $local_spl")
      end

    end
    if spl.alg.thin
      samples[i].value = Sample(varInfo).value
    end
    ProgressMeter.next!(spl.info[:progress])

  end

  Chain(0, samples)    # wrap the result by Chain
end


const N = parse(Int, ARGS[1])
const K_SITES = parse(Int, ARGS[2])
const MODE = Symbol(ARGS[3])  # kept as the CSV/plot label
const BOXED = MODE === :boxed
const N_ENTITIES = parse(Int, ARGS[4])

using Ark
using BenchmarkTools

const RT_SECONDS = 5
const RT_SAMPLES = 50

struct CompN{K}
    x::Float64
    y::Float64
end

function work end

function define_work()
    types = [CompN{i} for i in 1:N]
    body = Expr[:(e = new_entity!(world, ()))]
    for s in 1:K_SITES
        a = types[s]
        b = types[s + K_SITES]
        push!(body, :(add_components!(world, e, ($(a)(1.0, 1.0),))))
        push!(body, :(exchange_components!(world, e; add=($(b)(1.0, 1.0),), remove=($(a),))))
        push!(body, :(remove_components!(world, e, ($(b),))))
    end
    push!(body, :(return e))
    @eval function work(world)
        $(body...)
    end
    return nothing
end

function work_many!(world)
    for _ in 1:N_ENTITIES
        work(world)
    end
    return nothing
end

function measure()
    types = [CompN{i} for i in 1:N]
    ctor = @timed World(types...; boxed=BOXED)
    ops = @timed work(ctor.value)
    return (ctor.compile_time, ops.compile_time)
end

function measure_runtime(types)
    cold = @belapsed work_many!(w) setup = (w = World($types...; boxed=$BOXED)) evals = 1 samples = RT_SAMPLES seconds =
        RT_SECONDS

    warm = World(types...; boxed=BOXED)
    work_many!(warm)
    steady = @belapsed work_many!($warm) setup = (reset!($warm)) evals = 1 samples = RT_SAMPLES seconds = RT_SECONDS

    return cold, steady
end

define_work()

sc, so = measure()

mem = Sys.maxrss()

types = [CompN{i} for i in 1:N]
rt_cold, rt_steady = measure_runtime(types)

println("$N,$MODE,$sc,$so,$mem,$rt_cold,$rt_steady")

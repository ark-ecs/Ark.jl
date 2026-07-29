
const N = parse(Int, ARGS[1])
const K_SITES = parse(Int, ARGS[2])
const MODE = Symbol(ARGS[3])
# Entities created per runtime sample. `work` creates one entity and performs three structural
# operations on it, so a sample is this many entities and three times as many operations.
const N_ENTITIES = parse(Int, ARGS[4])

using Ark
using BenchmarkTools

# Budget per runtime measurement. Two of them per mode per sweep point, so this is the knob
# that decides how much the runtime columns add to the sweep.
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
        a = types[s]              # distinct typ per site
        b = types[s + K_SITES]    # second distinct type per site
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
    ctor = @timed World(types...; mode=MODE)
    ops = @timed work(ctor.value)
    return (ctor.compile_time, ops.compile_time)
end

# Runtime of the same structural operations, once compiled. Two variants, because the two
# answers are different and both are interesting:
#
#   - `cold`: every sample starts from a brand-new world, so the loop pays for creating the
#     tables, allocating the columns and growing the entity index as it goes. This is what a
#     program building its world for the first time actually experiences.
#   - `steady`: one warm-up pass has already created every table and grown every column, and
#     `reset!` empties them without handing the capacity back, so each sample measures the
#     structural operations alone.
function measure_runtime(types)
    cold = @belapsed work_many!(w) setup = (w = World($types...; mode=$MODE)) evals = 1 samples = RT_SAMPLES seconds =
        RT_SECONDS

    warm = World(types...; mode=MODE)
    work_many!(warm)
    steady = @belapsed work_many!($warm) setup = (reset!($warm)) evals = 1 samples = RT_SAMPLES seconds = RT_SECONDS

    return cold, steady
end

define_work()

sc, so = measure()

# Read before the runtime benchmarks: this column is the memory footprint of *compiling* each
# mode, and the benchmarks below churn through millions of entities, which would swamp it.
mem = Sys.maxrss()

types = [CompN{i} for i in 1:N]
rt_cold, rt_steady = measure_runtime(types)

println("$N,$MODE,$sc,$so,$mem,$rt_cold,$rt_steady")

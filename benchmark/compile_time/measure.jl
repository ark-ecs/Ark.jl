
const N = parse(Int, ARGS[1])
const K_SITES = parse(Int, ARGS[2])
const erased = parse(Bool, ARGS[3])

using Ark

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

function measure()
    types = [CompN{i} for i in 1:N]
    ctor = @timed World(types...; erased=erased)
    ops = @timed work(ctor.value)
    return (ctor.compile_time, ops.compile_time)
end

define_work()

sc, so = measure()

# Peak resident set size of this worker process (bytes) after doing all the compilation
# and structural work above - a proxy for the memory footprint of the two dispatch modes.
mem = Sys.maxrss()

println("$N,$(erased ? "erased" : "default"),$sc,$so,$mem")

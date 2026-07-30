
using Pkg
using Preferences
using Test

# TODO: re-enable when fixed on the Julia side.
@static if VERSION < v"1.13.0-DEV"
    Pkg.add("JET")
    using JET
end
const RUN_JET = "CI" in keys(ENV) && VERSION >= v"1.12.0" && isempty(VERSION.prerelease)

include("include_internals.jl")

if "--large-world" in ARGS
    include("setup_large.jl")
else
    include("setup_default.jl")
end

include("TestTypes.jl")

# Is `r` anchored in `Ark.name`, i.e. is that the innermost frame of its stack trace?
# `RuntimeDispatchReport` only prints the dispatched signature, so the offending method
# cannot be recognised from `sprint(show, r)` alone.
function is_report_in(r, name::Symbol)
    hasproperty(r, :vst) || return false
    isempty(r.vst) && return false
    linfo = last(r.vst).linfo
    linfo isa Core.MethodInstance || return false
    def = linfo.def
    return def isa Method && def.module === Ark && def.name === name
end

# JET reports that are known false positives, or that report dispatch which is there by
# design. Shared by the `report_package` check in `test_quality.jl` and by the
# `@test_opt_filtered` sites in the world suites.
function is_known_false_positive(r)
    msg = sprint(show, r)
    return occursin(
        "ArgumentError: either components to add or to remove must be given for exchange_components!",
        msg,
    ) ||
           (occursin("_valtuple(::Tuple)", msg) && occursin("Core.TypeofVararg", msg)) ||
           (occursin("_relation_types_and_targets", msg) && occursin("Core.TypeofVararg", msg)) ||
           # `_build_erased!` constructs a `FunctionWrapper` from a column whose concrete
           # type is deliberately outside the type domain in `:boxed` mode, so
           # specialising the wrapper constructor on it can only happen at runtime: that
           # dispatch *is* the type-erasure mechanism. It is `@noinline` and runs at most
           # once per (operation, component) for the lifetime of a world.
           (
        occursin("runtime dispatch detected", msg) &&
        is_report_in(r, :_build_erased!)
    )
end

# `JET.@test_opt`, except that reports accepted by `is_known_false_positive` are dropped
# before the assertion.
macro test_opt_filtered(args...)
    report = Expr(
        :macrocall, Expr(:., :JET, QuoteNode(Symbol("@report_opt"))), __source__, args...
    )
    return quote
        local filtered = filter(!is_known_false_positive, JET.get_reports($(esc(report))))
        isempty(filtered) || println(filtered)
        @test isempty(filtered)
    end
end

# Suites that build worlds without an explicit `mode`, so they exercise whichever
# mode the current pass selects. Run once per entry of `WORLD_MODES`.
const WORLD_SUITES = [
    "test_world.jl",
    "test_cache.jl",
    "test_filter.jl",
    "test_query.jl",
    "test_event.jl",
    "test_relations.jl",
    "test_archetype.jl",
    "test_structarray.jl",
    "test_readme.jl",
    "test_entity.jl",
    "test_shuffle.jl",
    "test_sort.jl",
    "test_partition.jl",
    "test_unchecked.jl",
    "test_indexing_api.jl",
    "test_kernels.jl",
    "test_command_buffer.jl",
    "test_graph.jl",
    "test_gpu_vector.jl",
]

# Suites that never construct a world, or that pick their modes explicitly.
# Running them once is enough.
const MODE_AGNOSTIC_SUITES = [
    "test_util.jl",
    "test_pool.jl",
    "test_lock.jl",
    "test_mask.jl",
    "test_registry.jl",
    "test_vec_map.jl",
    "test_linear_map.jl",
    "test_quality.jl",
]

for suite in MODE_AGNOSTIC_SUITES
    include(suite)
end

N_fake == 0 && include("test_erased.jl")
N_fake == 0 && include("test_boxed.jl")

for world_mode in WORLD_MODES
    DEFAULT_WORLD_MODE[] = world_mode
    @testset "world mode :$(world_mode)" begin
        for suite in WORLD_SUITES
            include(suite)
        end
    end
end

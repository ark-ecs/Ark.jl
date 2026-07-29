
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

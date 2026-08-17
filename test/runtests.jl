
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

const MODE_AGNOSTIC_SUITES = [
    "test_util.jl",
    "test_pool.jl",
    "test_lock.jl",
    "test_mask.jl",
    "test_registry.jl",
    "test_vec_map.jl",
    "test_linear_map.jl",
    "test_disk_vector.jl",
    "test_quality.jl",
    "test_unique_vector.jl",
]

for suite in MODE_AGNOSTIC_SUITES
    include(suite)
end

for world_boxed in WORLD_MODES
    DEFAULT_WORLD_BOXED[] = world_boxed
    @testset "world mode :$(world_boxed ? :boxed : :specialized)" begin
        for suite in WORLD_SUITES
            include(suite)
        end
    end
end


using Pkg
using Preferences
using Test

@static if VERSION < v"1.13.0-DEV"
    Pkg.add("JET")
    using JET
    const RUN_JET = true
else
    const RUN_JET = false
end

include("include_internals.jl")

include("setup.jl")
if "--large-world" in ARGS
    include("setup_large.jl")
else
    include("setup_default.jl")
end

include("TestTypes.jl")

include("test_util.jl")
include("test_world.jl")
include("test_cache.jl")
include("test_filter.jl")
include("test_query.jl")
include("test_event.jl")
include("test_relations.jl")
include("test_archetype.jl")
include("test_structarray.jl")
include("test_readme.jl")
include("test_entity.jl")
include("test_pool.jl")
include("test_lock.jl")
include("test_mask.jl")
include("test_registry.jl")
include("test_vec_map.jl")
include("test_linear_map.jl")
include("test_graph.jl")
include("test_gpu_vector.jl")
include("test_quality.jl")

if "CI" in keys(ENV) && VERSION < v"1.13" && isempty(VERSION.prerelease) && !("--large-world" in ARGS)
    Pkg.activate("ext")
    Pkg.instantiate()
    Pkg.develop(path="..")
    include("ext/runtests.jl")
end

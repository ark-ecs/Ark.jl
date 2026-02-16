
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

include("setup.jl")
if "--large-world" in ARGS
    include("setup_large.jl")
else
    include("setup_default.jl")
end

include("TestTypes.jl")

include("test_lock.jl")


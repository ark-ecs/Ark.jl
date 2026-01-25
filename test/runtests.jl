
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

include("test_unchecked.jl")
include("test_quality.jl")

if "CI" in keys(ENV) && VERSION < v"1.13" && isempty(VERSION.prerelease) && !("--large-world" in ARGS)
    Pkg.activate("ext")
    Pkg.instantiate()
    Pkg.develop(path="..")
    include("ext/runtests.jl")
end

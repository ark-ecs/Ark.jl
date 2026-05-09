
using Preferences

set_preferences!("Ark", "THREAD_SAFE_LOCK" => "false")

pushfirst!(LOAD_PATH, normpath(joinpath(@__DIR__, "..", "..")))

using Ark
using Test

include("TestADTypes.jl")

include("test_AD_interop.jl")

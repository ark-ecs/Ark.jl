
using Preferences

set_preferences!("Ark", "THREAD_SAFE_LOCK" => "false")

using Ark
using Test

include("TestADTypes.jl")

include("test_AD_interop.jl")

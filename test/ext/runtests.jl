
using Ark
using Preferences
using Test

@set_preferences!("THREAD_SAFE_LOCK" => "false")

include("test_mooncake_interop.jl")

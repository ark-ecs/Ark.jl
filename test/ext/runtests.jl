
using Preferences

set_preferences!("Ark", "THREAD_SAFE_LOCK" => "false")

using Ark
using Test

include("test_mooncake_interop.jl")

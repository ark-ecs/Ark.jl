
using Preferences

set_preferences!("Ark", "THREAD_SAFE_LOCK" => "false")

using Ark
using Test

include("../TestTypes.jl")

include("test_mooncake_interop.jl")

using Ark
using BenchmarkTools
using Chairmarks

const SECONDS = 0.5
const SUITE = BenchmarkGroup()

include("BenchTypes.jl")

include("bench_callback.jl")
include("bench_events.jl")
include("bench_mask_contains_all.jl")
include("bench_mask_contains_any.jl")
include("bench_create_mask.jl")
include("bench_set_mask.jl")
include("bench_is_zero_mask.jl")
include("bench_lock_unlock.jl")
include("bench_structarray.jl")
include("bench_get_map.jl")

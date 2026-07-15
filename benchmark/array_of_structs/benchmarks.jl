using Ark
using Chairmarks

const SECONDS = 0.5
const SUITE = BenchmarkGroup()

include("BenchTypes.jl")

include("bench_ark.jl")
include("bench_aos_outer.jl")
include("bench_aos_flat.jl")
include("bench_aos_immutable.jl")

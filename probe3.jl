# Same cached-CuArray scheme as probe2.jl, but built on the proposed public
# CUDA.unsafe_wrap! API (branch unsafe_wrap-inplace) instead of CUDA internals.
#
# Needs an environment where both the dev CUDA and its local CUDACore are
# developed (Pkg.develop on the parent does NOT pick up the workspace CUDACore):
#   Pkg.develop(path="/home/bob/.julia/dev/CUDA")
#   Pkg.develop(path="/home/bob/.julia/dev/CUDA/CUDACore")

using CUDA, BenchmarkTools

const CuUnifiedVector{T} = CuArray{T,1,CUDA.UnifiedMemory}

# Cache entry: holds the column too, so the wrapper can never outlive it.
mutable struct CachedColumn{T}
    const arr::CuUnifiedVector{T}
    col::Vector{T}
end

CachedColumn(v::Vector{T}) where {T} =
    CachedColumn{T}(unsafe_wrap(CuUnifiedVector{T}, v), v)

# unsafe_wrap! no-ops when the column didn't move or resize, so just call it
# unconditionally before each use.
@inline refresh!(c::CachedColumn) = CUDA.unsafe_wrap!(c.arr, c.col)

function scale_kernel!(a, s)
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    if i <= length(a)
        @inbounds a[i] *= s
    end
    return
end

N = 1024
v = ones(Float32, N)
c = CachedColumn(v)

# correctness: kernel through the cached CuArray (normal @cuda path w/ cudaconvert)
arr = refresh!(c)
CUDA.@sync @cuda threads=256 blocks=cld(length(arr),256) scale_kernel!(arr, 2.0f0)
println("kernel via cached CuArray: ", all(v .== 2f0) ? "OK" : "WRONG")

# host-side CuArray semantics work too
println("sum via GPUArrays mapreduce: ", sum(refresh!(c)) == 2f0*N ? "OK" : "WRONG")
println("broadcast: ", Array(refresh!(c) .+ 1f0)[1] == 3f0 ? "OK" : "WRONG")

# correctness across a resize! that moves the buffer
old_ptr = pointer(v)
resize!(v, 1_000_000); fill!(v, 1f0)
println("buffer moved: ", pointer(v) !== old_ptr)
arr = refresh!(c)
println("dims tracked: ", size(arr) == (1_000_000,))
CUDA.@sync @cuda threads=256 blocks=cld(length(arr),256) scale_kernel!(arr, 3.0f0)
println("kernel after realloc: ", all(v .== 3f0) ? "OK" : "WRONG")

# benchmarks
b1 = @benchmark refresh!($c)                       # fast path: nothing changed
println("refresh! (no change):    ", minimum(b1.times), " ns, ",
        b1.allocs, " allocs, ", b1.memory, " bytes")

vlen = length(v)
b2 = @benchmark refresh!($c) setup=(resize!($c.col, $vlen - 1);
                                    refresh!($c);
                                    resize!($c.col, $vlen)) evals=1
println("refresh! (length only):  ", minimum(b2.times), " ns, ",
        b2.allocs, " allocs, ", b2.memory, " bytes")

v2 = copy(v)   # alternate between two buffers to force the re-pointing path
b3 = @benchmark refresh!($c) setup=($c.col = $c.col === $v ? $v2 : $v) evals=1
println("refresh! (ptr changed):  ", minimum(b3.times), " ns, ",
        b3.allocs, " allocs, ", b3.memory, " bytes")

b4 = @benchmark CachedColumn($v)                   # one-time creation cost
println("initial CachedColumn:    ", minimum(b4.times), " ns, ",
        b4.allocs, " allocs, ", b4.memory, " bytes")

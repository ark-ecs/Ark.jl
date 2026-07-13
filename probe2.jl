# Prototype of the cached-CuArray scheme for Ark's unsafe_unwrap:
# one CuArray wrapper per column, created once (allocating), then refreshed
# in-place on each use (non-allocating unless the column buffer moved).

using CUDA, BenchmarkTools
import CUDA.CUDACore: Managed, UnifiedMemory
import CUDA.CUDACore.GPUArrays: DataRef

const CuUnifiedVector{T} = CuArray{T,1,UnifiedMemory}

# Cache entry: holds the column too, so the wrapper can never outlive it.
mutable struct CachedColumn{T}
    const arr::CuUnifiedVector{T}
    col::Vector{T}
    ptr::Ptr{T}
end

function _wrap_unified(v::Vector{T}) where {T}
    p = pointer(v)
    sz = length(v) * sizeof(T)
    mem = UnifiedMemory(CUDA.context(), reinterpret(CuPtr{Nothing}, p), sz)
    data = DataRef(Returns(nothing), Managed(mem))   # non-owning
    arr = CuArray{T,1}(data, (length(v),))
    return CachedColumn{T}(arr, v, p)
end

@inline function refresh!(c::CachedColumn{T}) where {T}
    v = c.col
    p = pointer(v)
    n = length(v)
    arr = c.arr
    if p !== c.ptr
        # buffer moved: swap in a new Managed (only alloc on this path)
        mem = UnifiedMemory(CUDA.context(), reinterpret(CuPtr{Nothing}, p),
                            n * sizeof(T))
        arr.data.rc.obj = Managed(mem)
        c.ptr = p
    end
    if arr.dims !== (n,)
        arr.dims = (n,)
        arr.maxsize = n * sizeof(T)
    end
    return arr
end

function scale_kernel!(a, s)
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    if i <= length(a)
        @inbounds a[i] *= s
    end
    return
end

N = 1024
v = ones(Float32, N)
c = _wrap_unified(v)

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

b3 = @benchmark refresh!($c) setup=($c.ptr = Ptr{Float32}(0)) evals=1
println("refresh! (ptr changed):  ", minimum(b3.times), " ns, ",
        b3.allocs, " allocs, ", b3.memory, " bytes")

b4 = @benchmark _wrap_unified($v)                  # one-time creation cost
println("initial _wrap_unified:   ", minimum(b4.times), " ns, ",
        b4.allocs, " allocs, ", b4.memory, " bytes")

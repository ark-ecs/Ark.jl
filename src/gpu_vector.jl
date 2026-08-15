
"""
    GPUVector

A vector implementation that uses unified memory for mixed CPU/GPU operations.
The implementation is compatible with CUDA.jl, Metal.jl, oneAPI.jl and OpenCL.jl.
When passed as a storage the back-end must be specified (either :CUDA, :Metal,
:oneAPI, :OpenCL or :CPU).

The `:CPU` back-end is always available and stores the elements in a plain
`Vector`. It requires no GPU package and is useful for testing and for running
GPU-shaped code on machines without a device.

On back-ends with more than one device, the storage can be pinned to a specific
device by pairing the back-end with a zero-based device ordinal, like
`(:CUDA, 1)` for the second GPU of the system. Alternatively, a device object
can be passed through `Storage(GPUVector{:CUDA}, device)`, which is translated
into the ordinal-based form. All memory of the storage is then allocated on that
device, including re-allocations during growth. Device selection is currently
supported for the :CUDA, :Metal and :oneAPI back-ends. Kernels operating on the
components still have to be launched on the matching device (e.g. by using
`CUDA.device!`).

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUVector{:CUDA}},
    Velocity => Storage{GPUVector{:CUDA}},
)
```

```
using CUDA

world = World(
    Position => Storage{GPUVector{(:CUDA, 1)}},
    Velocity => Storage{GPUVector{(:CUDA, 1)}},
)
```

```
using CUDA

world = World(
    Position => Storage(GPUVector{:CUDA}, CuDevice(1)),
    Velocity => Storage(GPUVector{:CUDA}, CuDevice(1)),
)
```

```
world = World(
    Position => Storage{GPUVector{:CPU}},
    Velocity => Storage{GPUVector{:CPU}},
)
```
"""
mutable struct GPUVector{B,T,M} <: AbstractVector{T}
    mem::M
    host::Vector{T}
    len::Int
end

function _gpuvector_type end

_gpuvector_type(::Type{T}, ::Val{:CPU}) where {T} = Vector{T}

function _gpuvector_type(::Type{T}, v::Val{B}) where {T,B}
    if B isa Tuple{Symbol,<:Integer}
        return _gpuvector_type(T, Val{B[1]}())
    end
    throw(MethodError(_gpuvector_type, (T, v)))
end

function _gpu_backend(::Type{<:GPUVector{B}}) where {B}
    return B
end

function _gpuvector_device end

function _gpuvector_device(::Val{B}) where {B}
    B isa Tuple{Symbol,<:Integer} && return _gpuvector_pinned_device(Val{B[1]}(), B[2])
    return nothing
end

function _gpuvector_pinned_device end

function _gpuvector_pinned_device(::Val{B}, ::Integer) where {B}
    throw(ArgumentError(lazy"GPU device selection is not supported for the $B back-end"))
end

function _gpuvector_withdev end

@inline _gpuvector_withdev(f, ::Nothing) = f()

function _gpuvector_ordinal end

function _gpuvector_ordinal(device)
    throw(ArgumentError(lazy"GPU device lookup is not supported for devices of type $(typeof(device))"))
end

@inline function _gpuvector_device_check(B)
    B isa Tuple{Symbol,<:Integer} &&
        throw(ArgumentError("storage is already pinned to a GPU device"))
    return
end

function Storage(::Type{GPUVector{B}}, device) where {B}
    _gpuvector_device_check(B)
    return Storage{GPUVector{(B, _gpuvector_ordinal(device))}}()
end

function Storage(::Type{A}, device) where {A<:AbstractVector}
    throw(ArgumentError(lazy"storage mode $A does not support GPU device selection"))
end

function _gpuvectorview_type(::Type{GPUVector{B,T,M}}) where {B,T,M}
    return GPUVectorView{B,T,GPUVector{B,T,M},SubArray{T,1,Vector{T},Tuple{UnitRange{Int}},true}}
end

function _gpuvector_hostwrap(mem::AbstractVector)
    throw(ArgumentError(lazy"$(typeof(mem)) does not support host wrapping"))
end

_gpuvector_hostwrap(mem::Vector) = mem

function GPUVector{B,T,M}(mem::M, len::Integer) where {B,T,M}
    host = _gpuvector_hostwrap(mem)
    return GPUVector{B,T,M}(mem, host, len)
end

function GPUVector{B,T,M}() where {B,T,M}
    dev = _gpuvector_device(Val{B}())
    mem = _gpuvector_withdev(() -> M(undef, 0), dev)
    return GPUVector{B,T,M}(mem, 0)
end

Base.size(gv::GPUVector) = (length(gv),)
Base.length(gv::GPUVector) = gv.len

Base.@propagate_inbounds function Base.getindex(gv::GPUVector, i::Int)
    @boundscheck checkbounds(gv, i)
    return gv.host[i]
end

Base.@propagate_inbounds function Base.setindex!(gv::GPUVector, v, i::Int)
    @boundscheck checkbounds(gv, i)
    gv.host[i] = v
    return v
end

function _resize_mem!(gv::GPUVector{B}, new_len::Integer) where {B}
    if length(gv.mem) < new_len
        new_cap = max(new_len, 2 * length(gv.mem))
        dev = _gpuvector_device(Val{B}())
        _gpuvector_withdev(dev) do
            new_mem = typeof(gv.mem)(undef, new_cap)
            unsafe_copyto!(new_mem, 1, gv.mem, 1, length(gv))
            gv.mem = new_mem
            gv.host = _gpuvector_hostwrap(new_mem)
            return nothing
        end
    end
    return
end

function Base.resize!(gv::GPUVector, new_len::Integer)
    _resize_mem!(gv, new_len)
    gv.len = new_len
    return gv
end

function Base.empty!(gv::GPUVector)
    gv.len = 0
    return gv
end

function Base.push!(gv::GPUVector, v)
    new_len = gv.len + 1
    resize!(gv, new_len)
    @inbounds gv[new_len] = v
    return gv
end

function Base.pop!(gv::GPUVector)
    gv.len == 0 && throw(ArgumentError("array must be non-empty"))
    gv.len -= 1
    return gv
end

function Base.sizehint!(gv::GPUVector, new_len::Integer)
    _resize_mem!(gv, new_len)
    return gv
end

@inline function _gpuvector_copy_bounds(dest, doffs::Integer, src, soffs::Integer, n::Integer)
    n < 0 && throw(ArgumentError("Can't copy a negative number of elements"))
    if doffs < 1 || doffs + n - 1 > length(dest) || soffs < 1 || soffs + n - 1 > length(src)
        throw(BoundsError((dest, src), (doffs, soffs)))
    end
    return
end

function Base.copyto!(gv::GPUVector, doffs::Integer, src::AbstractVector, soffs::Integer, n::Integer)
    n == 0 && return gv
    _gpuvector_copy_bounds(gv, doffs, src, soffs, n)
    copyto!(gv.host, doffs, src, soffs, n)
    return gv
end

function Base.copyto!(gv::GPUVector, doffs::Integer, src::GPUVector, soffs::Integer, n::Integer)
    n == 0 && return gv
    _gpuvector_copy_bounds(gv, doffs, src, soffs, n)
    unsafe_copyto!(gv, doffs, src, soffs, n)
    return gv
end

function Base.unsafe_copyto!(gv::GPUVector, doffs::Integer, src::GPUVector, soffs::Integer, n::Integer)
    unsafe_copyto!(gv.mem, doffs, src.mem, soffs, n)
    return gv
end

function Base.similar(gv::GPUVector{B,T,M}, ::Type{T}, size::Dims{1}) where {B,T,M}
    dev = _gpuvector_device(Val{B}())
    mem = _gpuvector_withdev(() -> M(undef, size[1]), dev)
    return GPUVector{B,T,M}(mem, size[1])
end

Base.IndexStyle(::Type{<:GPUVector}) = IndexLinear()

struct GPUVectorView{B,T,GV<:GPUVector,HV<:AbstractVector{T}} <: AbstractVector{T}
    gv::GV
    rng::UnitRange{Int}
    host::HV
end

function _gpuvector_view(gv::GPUVector{B,T,M}, rng::AbstractUnitRange) where {B,T,M}
    r = UnitRange{Int}(rng)
    hv = view(gv.host, r)
    GPUVectorView{B,T,typeof(gv),typeof(hv)}(gv, r, hv)
end

function Adapt.adapt_structure(to, v::GPUVectorView)
    return Adapt.adapt(to, view(v.gv.mem, v.rng))
end

Base.size(v::GPUVectorView) = size(v.host)
Base.IndexStyle(::Type{<:GPUVectorView}) = IndexLinear()
Base.parent(v::GPUVectorView) = v.gv

Base.@propagate_inbounds Base.getindex(v::GPUVectorView, i::Int) = v.host[i]

Base.@propagate_inbounds function Base.setindex!(v::GPUVectorView, x, i::Int)
    v.host[i] = x
    return x
end

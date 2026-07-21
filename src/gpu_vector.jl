
"""
    GPUVector

A vector implementation that uses unified memory for mixed CPU/GPU operations.
The implementation is compatible with CUDA.jl, Metal.jl, oneAPI.jl and OpenCL.jl.
When passed as a storage the back-end must be specified (either :CUDA, :Metal,
:oneAPI, :OpenCL or :CPU).

The `:CPU` back-end is always available and stores the elements in a plain
`Vector`. It requires no GPU package and is useful for testing and for running
GPU-shaped code on machines without a device.

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUVector{:CUDA}},
    Velocity => Storage{GPUVector{:CUDA}},
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

function _gpu_backend(::Type{<:GPUVector{B}}) where {B}
    return B
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
    return GPUVector{B,T,M}(M(), 0)
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

function _resize_mem!(gv::GPUVector, new_len::Integer)
    if length(gv.mem) < new_len
        new_cap = max(new_len, 2 * length(gv.mem))
        new_mem = typeof(gv.mem)(undef, new_cap)
        copyto!(new_mem, 1, gv.mem, 1, length(gv))
        gv.mem = new_mem
        gv.host = _gpuvector_hostwrap(new_mem)
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

function Base.copyto!(gv::GPUVector, doffs::Integer, src::AbstractVector, soffs::Integer, n::Integer)
    copyto!(gv.host, doffs, src, soffs, n)
    return gv
end

function Base.copyto!(gv::GPUVector, doffs::Integer, src::GPUVector, soffs::Integer, n::Integer)
    copyto!(gv.host, doffs, src.host, soffs, n)
    return gv
end

function Base.unsafe_copyto!(gv::GPUVector, doffs::Integer, src::GPUVector, soffs::Integer, n::Integer)
    unsafe_copyto!(gv.host, doffs, src.host, soffs, n)
    return gv
end

function Base.similar(gv::GPUVector{B,T,M}, ::Type{T}, size::Dims{1}) where {B,T,M}
    return GPUVector{B,T,M}(M(undef, size), size[1])
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

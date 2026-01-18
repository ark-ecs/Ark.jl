
"""
    GPUVector

A vector implementation that uses unified memory for mixed CPU/GPU operations.
The implementation is compatible with CUDA.jl, Metal.jl, oneAPI.jl and OpenCL.jl.
When passed as a storage the back-end must be specified (either :CUDA, :Metal,
:oneAPI or :OpenCL).

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUVector{:CUDA}},
    Velocity => Storage{GPUVector{:CUDA}},
)
```
"""
mutable struct GPUVector{B,T,M} <: AbstractVector{T}
    mem::M
    len::Int
end

function _gpuvector_type end

function _gpuvectorview_type(t::Type, k::Val)
    _gpuvector_type(t, k)
end

function GPUVector{B,T,M}() where {B,T,M}
    return GPUVector{B,T,M}(M(), 0)
end

Base.size(gv::GPUVector) = (length(gv),)
Base.length(gv::GPUVector) = gv.len

Base.@propagate_inbounds function Base.getindex(gv::GPUVector, i::Int)
    @boundscheck 0 < i <= length(gv)
    return gv.mem[i]
end

Base.@propagate_inbounds function Base.setindex!(gv::GPUVector, v, i::Int)
    @boundscheck 0 < i <= length(gv)
    gv.mem[i] = v
    return v
end

function _resize_mem!(gv::GPUVector, new_len::Integer)
    if length(gv.mem) < new_len
        new_cap = max(new_len, 2 * length(gv.mem))
        new_mem = typeof(gv.mem)(undef, new_cap)
        copyto!(new_mem, 1, gv.mem, 1, length(gv))
        gv.mem = new_mem
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
    @inbounds gv.mem[new_len] = v
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
    copyto!(gv.mem, doffs, src, soffs, n)
    return gv
end

function Base.similar(gv::GPUVector{B,T,M}, ::Type{T}, size::Dims{1}) where {B,T,M}
    return GPUVector{B,T,M}(M(undef, size), size[1])
end

Base.IndexStyle(::Type{<:GPUVector}) = IndexLinear()

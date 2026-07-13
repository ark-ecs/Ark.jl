
"""
    GPUVector

A vector implementation that uses unified memory for mixed CPU/GPU operations.
The implementation is compatible with CUDA.jl, Metal.jl, oneAPI.jl and OpenCL.jl.
When passed as a storage the back-end must be specified (either :CUDA, :Metal,
:oneAPI or :OpenCL).

On back-ends that support it (currently CUDA), CPU-side accesses go through a
zero-copy host `Vector` aliasing the same unified memory, which is much faster
than scalar indexing of the back-end array. GPU kernels keep operating on the
back-end array. This bypasses the back-end's implicit synchronization: after
launching kernels that touch a component, synchronize the device before
accessing that component on the CPU (including through structural operations).

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUVector{:CUDA}},
    Velocity => Storage{GPUVector{:CUDA}},
)
```
"""
mutable struct GPUVector{B,T,M,H} <: AbstractVector{T}
    mem::M
    host::Vector{T}
    len::Int
end

function _gpu_backend(::Type{<:GPUVector{B}}) where {B}
    return B
end

function _gpuvector_type end

function _gpuvectorview_type(t::Type, k::Val)
    _gpuvector_type(t, k)
end

@generated function _gpuvectorview_type(::Type{GPUVector{B,T,M,H}}) where {B,T,M,H}
    if H
        return :(GPUVectorView{B,T,GPUVector{B,T,M,H},SubArray{T,1,Vector{T},Tuple{UnitRange{Int}},true}})
    else
        return :(_gpuvectorview_type(T, $(Val{B}())))
    end
end

_gpuvector_has_hostwrap(::Val) = false

function _gpuvector_hostwrap end

function GPUVector{B,T,M,H}(mem::M, len::Integer) where {B,T,M,H}
    host = H ? _gpuvector_hostwrap(mem) : T[]
    return GPUVector{B,T,M,H}(mem, host, len)
end

function GPUVector{B,T,M,H}() where {B,T,M,H}
    return GPUVector{B,T,M,H}(M(), 0)
end

function GPUVector{B,T,M}(args...) where {B,T,M}
    H = _gpuvector_has_hostwrap(Val{B}())
    return GPUVector{B,T,M,H}(args...)
end

Base.size(gv::GPUVector) = (length(gv),)
Base.length(gv::GPUVector) = gv.len

Base.@propagate_inbounds function Base.getindex(gv::GPUVector{B,T,M,H}, i::Int) where {B,T,M,H}
    if H
        return gv.host[i]
    else
        return gv.mem[i]
    end
end

Base.@propagate_inbounds function Base.setindex!(gv::GPUVector{B,T,M,H}, v, i::Int) where {B,T,M,H}
    if H
        gv.host[i] = v
    else
        gv.mem[i] = v
    end
    return v
end

function _resize_mem!(gv::GPUVector{B,T,M,H}, new_len::Integer) where {B,T,M,H}
    if length(gv.mem) < new_len
        new_cap = max(new_len, 2 * length(gv.mem))
        new_mem = typeof(gv.mem)(undef, new_cap)
        copyto!(new_mem, 1, gv.mem, 1, length(gv))
        gv.mem = new_mem
        if H
            gv.host = _gpuvector_hostwrap(new_mem)
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

function Base.copyto!(gv::GPUVector{B,T,M,H}, doffs::Integer, src::AbstractVector, soffs::Integer, n::Integer) where {B,T,M,H}
    if H
        copyto!(gv.host, doffs, src, soffs, n)
    else
        copyto!(gv.mem, doffs, src, soffs, n)
    end
    return gv
end

function Base.copyto!(gv::GPUVector{B,T,M,H}, doffs::Integer, src::GPUVector{B2,T2,M2,H2}, soffs::Integer, n::Integer) where {B,T,M,H,B2,T2,M2,H2}
    if H && H2
        copyto!(gv.host, doffs, src.host, soffs, n)
    else
        copyto!(gv.mem, doffs, src.mem, soffs, n)
    end
    return gv
end

function Base.unsafe_copyto!(gv::GPUVector{B,T,M,H}, doffs::Integer, src::GPUVector{B2,T2,M2,H2}, soffs::Integer, n::Integer) where {B,T,M,H,B2,T2,M2,H2}
    if H && H2
        unsafe_copyto!(gv.host, doffs, src.host, soffs, n)
    else
        unsafe_copyto!(gv.mem, doffs, src.mem, soffs, n)
    end
    return gv
end

function Base.similar(gv::GPUVector{B,T,M,H}, ::Type{T}, size::Dims{1}) where {B,T,M,H}
    return GPUVector{B,T,M,H}(M(undef, size), size[1])
end

Base.IndexStyle(::Type{<:GPUVector}) = IndexLinear()

"""
    GPUVectorView

Query view over a [`GPUVector`](@ref) column on back-ends that support
zero-copy host wrapping (currently CUDA). Scalar accesses on the CPU go
through the host wrapper at plain-`Vector` speed, while `Adapt` converts it
to a view of the back-end array, so it can be passed directly to GPU kernels.
The device view is only materialized on kernel launch; CPU-side use never
touches the back-end array.
"""
struct GPUVectorView{B,T,GV<:GPUVector,HV<:AbstractVector{T}} <: AbstractVector{T}
    gv::GV
    rng::UnitRange{Int}
    host::HV
end

@generated function _gpuvector_view(gv::GPUVector{B,T,M,H}, rng::AbstractUnitRange) where {B,T,M,H}
    if H
        quote
            r = UnitRange{Int}(rng)
            hv = view(gv.host, r)
            GPUVectorView{B,T,typeof(gv),typeof(hv)}(gv, r, hv)
        end
    else
        quote
            view(gv.mem, rng)
        end
    end
end

_gpuvector_devview(v::GPUVectorView) = view(v.gv.mem, v.rng)

Adapt.adapt_structure(to, v::GPUVectorView) = Adapt.adapt(to, _gpuvector_devview(v))

Base.size(v::GPUVectorView) = size(v.host)
Base.IndexStyle(::Type{<:GPUVectorView}) = IndexLinear()
Base.parent(v::GPUVectorView) = v.gv

Base.@propagate_inbounds Base.getindex(v::GPUVectorView, i::Int) = v.host[i]

Base.@propagate_inbounds function Base.setindex!(v::GPUVectorView, x, i::Int)
    v.host[i] = x
    return x
end

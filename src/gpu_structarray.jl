
struct _GPUStructArray{C,CS<:NamedTuple,N} <: _AbstractStructArray{C}
    _components::CS
end

@generated function _GPUStructArray(::Type{T}, ::Type{C}, cap=0) where {T,C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :($T{$t,1}), types)...)}})
    kv_exprs = [:($name = $T{$t,1}(undef, cap)) for (name, t) in zip(names, types)]
    return quote
        _GPUStructArray{$C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _GPUStructArray_type(::Type{T}, ::Type{C}) where {T,C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :($T{$t,1}), types)...)}})
    return quote
        _GPUStructArray{$C,$nt_type,$num_fields}
    end
end

@generated function Base.copyto!(
    dst::_AbstractStructArray{C},
    doffs::Integer,
    src::_AbstractStructArray{C},
    soffs::Integer,
    n::Integer,
) where {C}
    names = fieldnames(C)
    copyto_exprs = [
        :(copyto!(getfield(dst, :_components).$name, doffs, getfield(src, :_components).$name, soffs, n)) for name in names
    ]
    return Expr(:block, copyto_exprs..., :(dst))
end

Base.length(gsa::_GPUStructArray) = length(first(getfield(gsa, :_components)))

"""
    GPUSyncStructArray

A hybrid struct-of-arrays implementation that manages data synchronization between a CPU
[`StructArray`](@ref) and a GPU buffer. The implementation is compatible with all major
backends (CUDA.jl, AMDGPU.jl, Metal.jl and oneAPI.jl).

This struct acts as a storage type for components that require computation offloading with
SoA layout on GPU. By default, array operations are performed on the CPU. To perform
operations on the GPU, use [`gpuviews`](@ref) to obtain views of the underlying GPU device
buffers for each field.

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUSyncStructArray{CuArray}},
    Velocity => Storage{GPUSyncStructArray{CuArray}},
)
```
"""
mutable struct GPUSyncStructArray{C,AT,BT} <: AbstractVector{C}
    const vec::AT
    buffer::BT
    sync_cpu::Bool
    sync_gpu::Bool
end

function GPUSyncStructArray{C,AT,BT}() where {C,AT,BT}
    T = _gpuarray_type(BT)
    return GPUSyncStructArray{C,AT,BT}(StructArray(C), _GPUStructArray(T, C), true, true)
end

_gpuarray_type(::Type{_GPUStructArray{C,CS,N}}) where {C,CS,N} = fieldtypes(CS)[1].name.wrapper

"""
    gpuviews(gsa::GPUSyncStructArray; readonly::Bool=false)
    gpuviews(gsa::FieldViewable{<:Any, 1, <:GPUSyncStructArray}; readonly::Bool=false)

Return a tuple of views of the underlying GPU buffers for each field of the component type
stored in the [`GPUSyncStructArray`](@ref).

Invoking this function triggers a synchronization: if the GPU buffer is stale, data is
copied from the CPU to the GPU.

# Keyword Arguments

  - `readonly::Bool`: If set to `true`, indicates that the returned views will not be written to.

    **Performance Note:** Setting `readonly=true` prevents the array from marking the GPU data
    as "dirty" (desynchronized). This avoids an unnecessary copy back to the CPU on the next host
    access.

    **Warning:** The caller guarantees that no write operations occur when `readonly=true`.
    Modifying the views when this flag is set results in undefined behavior regarding data
    consistency.
"""
function gpuviews(gv::FieldViewable{<:Any,1,<:GPUSyncStructArray}; readonly::Bool=false)
    return gpuviews(parent(gv); readonly=readonly)
end

@generated function gpuviews(gsa::GPUSyncStructArray{C}; readonly::Bool=false) where {C}
    names = fieldnames(C)
    views_exprs = [
        :(view(getfield(gsa.buffer, :_components).$name, 1:length(gsa.vec))) for name in names
    ]
    views_tuple_expr = Expr(:tuple, views_exprs...)
    quote
        _resync_gpu!(gsa)
        if !readonly
            gsa.sync_cpu = false
        end
        return $views_tuple_expr
    end
end

function Base.similar(gv::GPUSyncStructArray{C,AT,BT}, ::Type{C}, size::Dims{1}) where {C,AT,BT}
    sa = StructArray(C)
    resize!(sa, size[1])
    T = _gpuarray_type(BT)
    return GPUSyncStructArray{C,AT,BT}(sa, _GPUStructArray(T, C), true, true)
end

function Base.view(gsa::GPUSyncStructArray, ::Colon)
    _resync_cpu!(gsa)
    return view(gsa.vec, 1:length(gsa))
end

function Base.view(gsa::GPUSyncStructArray, idx::AbstractUnitRange)
    _resync_cpu!(gsa)
    return view(gsa.vec, idx)
end

function Base.getproperty(gsa::GPUSyncStructArray, name::Symbol)
    _resync_cpu!(gsa)
    return getproperty(gsa.vec, name)
end

Base.eltype(::Type{<:GPUSyncStructArray{C}}) where {C} = C

function _resync_gpu!(gsa::GPUSyncStructArray{C,AT,BT}) where {C,AT,BT}
    if !gsa.sync_gpu
        if length(gsa.buffer) < length(gsa.vec)
            T = _gpuarray_type(BT)
            new_cap = max(length(gsa.vec), 2 * length(gsa.buffer))
            gsa.buffer = _GPUStructArray(T, C, new_cap)
        end
        copyto!(gsa.buffer, 1, gsa.vec, 1, length(gsa.vec))
        gsa.sync_gpu = true
    end
    return
end

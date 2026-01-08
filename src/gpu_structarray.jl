
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

Base.size(gsa::_GPUStructArray) = (length(gsa),)
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
@generated function gpuviews(gsa::GPUSyncStructArray{C}; readonly::Bool=false) where {C}
    names = fieldnames(C)
    views_exprs = [
        :(view(getfield(gsa, :buffer)._components.$name, 1:length(getfield(gsa, :vec)))) for name in names
    ]
    views_tuple_expr = Expr(:tuple, views_exprs...)
    quote
        _resync_gpu!(gsa)
        if !readonly
            setfield!(gsa, :sync_cpu, false)
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

Base.view(sa::GPUSyncStructArray, ::Colon) = view(sa, 1:length(sa))

@generated function Base.view(
    sa::S,
    idx::I,
) where {S<:GPUSyncStructArray{C},I<:AbstractUnitRange{T}} where {C,T<:Integer}
    return :(_GPUSyncStructArrayView{$C,$S,$I}(sa, idx))
end

function Base.getproperty(gsa::GPUSyncStructArray, name::Symbol)
    _resync_cpu!(gsa)
    return getproperty(getfield(gsa, :vec), name)
end

Base.eltype(::Type{<:GPUSyncStructArray{C}}) where {C} = C

function _resync_gpu!(gsa::GPUSyncStructArray{C,AT,BT}) where {C,AT,BT}
    if !getfield(gsa, :sync_gpu)
        vec = getfield(gsa, :vec)
        buffer = getfield(gsa, :buffer)
        if length(buffer) < length(vec)
            T = _gpuarray_type(BT)
            new_cap = max(length(vec), 2 * length(buffer))
            buffer = _GPUStructArray(T, C, new_cap)
            setfield!(gsa, :buffer, buffer)
        end
        copyto!(buffer, 1, vec, 1, length(vec))
        setfield!(gsa, :sync_gpu, true)
    end
    return
end

struct _GPUSyncStructArrayView{C,AT<:GPUSyncStructArray,I} <: AbstractArray{C,1}
    array::AT
    indices::I
end

@generated function _GPUSyncStructArrayView_type(::Type{T}, ::Type{ST}, ::Type{I}) where {T,ST,I}
    return :(_GPUSyncStructArrayView{T,ST,I})
end

Base.@propagate_inbounds function Base.getindex(sa::_GPUSyncStructArrayView, i::Int)
    return getindex(sa.array, i)
end

Base.@propagate_inbounds function Base.setindex!(sa::_GPUSyncStructArrayView, c::Any, i::Int)
    return setindex!(sa.array, c, i)
end

function Base.fill!(sa::_GPUSyncStructArrayView, value::Any)
    return fill!(sa.array, value)
end

Base.@propagate_inbounds function Base.iterate(sa::_GPUSyncStructArrayView)
    return iterate(sa.array)
end

Base.@propagate_inbounds function Base.iterate(sa::_GPUSyncStructArrayView, i::Int)
    return iterate(sa.array, i)
end

Base.size(sa::_GPUSyncStructArrayView) = (length(sa),)
Base.length(sa::_GPUSyncStructArrayView) = length(sa.indices)
Base.eltype(::Type{<:_GPUSyncStructArrayView{<:GPUSyncStructArray{C}}}) where C = C
Base.IndexStyle(::Type{<:_GPUSyncStructArrayView}) = IndexLinear()
Base.eachindex(sa::_GPUSyncStructArrayView) = eachindex(sa.array)
Base.firstindex(sa::_GPUSyncStructArrayView) = firstindex(sa.array)
Base.lastindex(sa::_GPUSyncStructArrayView) = lastindex(sa.array)

function Base.show(io::IO, a::_GPUSyncStructArrayView)
    return show(io, a.array)
end

unpack(a::_GPUSyncStructArrayView) = unpack(a.array)

function gpuviews(gv::_GPUSyncStructArrayView; readonly::Bool=false)
    return gpuviews(gv.array; readonly=readonly)
end

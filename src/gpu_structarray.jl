
struct GPUStructArray{C,CS<:NamedTuple,N} <: _AbstractStructArray{C}
    _components::CS
end

@generated function GPUStructArray(::Val{BT}, cap=0) where {BT}
	T = BT.body.name.Typeofwrapper.parameters[1]
	C = BT.body.parameters[1]
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :($T{$t,1}), types)...)}})
    kv_exprs = [:($name = $T{$t,1}(undef, cap)) for (name, t) in zip(names, types)]
    return quote
        GPUStructArray{$C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _GPUStructArray_type(::Type{T}, ::Type{C}) where {T,C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :($T{$t,1}), types)...)}})
    return quote
        GPUStructArray{$C,$nt_type,$num_fields}
    end
end

function Base.copyto!(
	dst::_AbstractStructArray{C}, 
	doffs::Integer, 
	src::_AbstractStructArray{C}, 
	soffs::Integer, 
	n::Integer
) where {C}
    names = fieldnames(C)
    copyto_exprs = [
        :(copyto!(getfield(dst, :_components).$name, 1, getfield(src, :_components).$name, 1, n)) for name in names
    ]
    return Expr(:block, copyto_exprs..., :(dst))
end

Base.length(gsa::GPUStructArray) = length(first(getfield(gsa, :_components)))

mutable struct GPUSyncStructArray{T,AT,BT} <: AbstractVector{T}
    const vec::AT
    buffer::BT
    sync_cpu::Bool
    sync_gpu::Bool
end

function GPUSyncStructArray{T,AT,BT}() where {T,AT,BT}
    return GPUSyncStructArray{T,AT,BT}(StructArray{T}(), GPUStructArray(Val{BT}()), true, true)
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

function Base.similar(gv::GPUSyncStructArray{T,AT,BT}, ::Type{T}, size::Dims{1}) where {T,AT,BT}
    sa = StructArray{T}()
    resize!(sa, size)
    return GPUSyncStructArray{T,AT,BT}(sa, GPUStructArray(Val{BT}(), new_cap), true, true)
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

Base.eltype(::Type{<:GPUSyncStructArray{StructArray{C}}}) where {C} = C

function _resync_gpu!(gsa::GPUSyncStructArray{AT,BT}) where {AT,BT}
    if !gsa.sync_gpu
        # TODO: maybe consider shrinking if CPU vector is much smaller
        # to save GPU space
        if length(gsa.buffer) < length(gsa.vec)
            new_cap = max(length(gsa.vec), 2 * length(gsa.buffer))
            gsa.buffer = GPUStructArray(Val{BT}(), new_cap)
        end
        copyto!(gsa.buffer, 1, gsa.vec, 1, length(gsa.vec))
        gsa.sync_gpu = true
    end
    return
end

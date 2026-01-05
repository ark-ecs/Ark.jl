
struct GPUStructArray{C,CS<:NamedTuple,N} <: _AbstractStructArray{C}
    _components::CS
end

@generated function GPUStructArray(::Val{BT}) where {BT}
	T = BT.body.name.Typeofwrapper.parameters[1]
	C = BT.body.parameters[1]
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :($T{$t,1}), types)...)}})
    kv_exprs = [:($name = $T{$t,1}()) for (name, t) in zip(names, types)]
    return quote
        GPUStructArray{$C,$nt_type,$num_fields}((; $(kv_exprs...)))
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
        :(copyto!(getfield(dst, :_components).$name, 1, getfield(src, :_components).$name, 1, n) for name in names
    ]
    return Expr(:block, copyto_exprs..., :(dst))
end

Base.size(gsa::GPUStructArray) = (length(gsa),)
Base.length(gsa::GPUStructArray) = length(first(getfield(gsa, :_components)))

mutable struct GPUSyncStructArray{AT,BT} <: AbstractVector{T}
    const vec::AT
    buffer::BT
    sync_cpu::Bool
    sync_gpu::Bool
end

function GPUSyncStructArray{T,BT}() where {T,BT}
    return GPUSyncStructArray{T,BT}(StructArray{T}(), GPUStructArray(Val{BT}()), true, true)
end

@generated function gpuviews(gsa::GPUSyncStructArray{C}; readonly::Bool=false) where {C}
	names = fieldnames(C)
    views_exprs = [
        :(view(getfield(gsa.buffer, :_components).$name, 1:length(gsa.vec))) for name in names
    ]
    views_tuple_expr = Expr(:tuple, views_exprs...)
	quote
	    _resync_gpu!(gv, readonly)
	    if !readonly
	        gv.sync_cpu = false
	    end
	    return $views_tuple_expr
	end
end


Base.@propagate_inbounds function Base.getindex(gv::GPUSyncStructArray, i::Int)
    _resync_cpu!(gv)
    return gv.vec[i]
end

Base.@propagate_inbounds function Base.setindex!(gv::GPUSyncStructArray, v, i::Int)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    gv.vec[i] = v
    return v
end

function Base.resize!(gv::GPUSyncStructArray, new_len::Integer)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    resize!(gv.vec, new_len)
    return gv
end

function Base.empty!(gv::GPUSyncStructArray)
    gv.sync_gpu = false
    empty!(gv.vec)
    return gv
end

function Base.push!(gv::GPUSyncStructArray, v)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    push!(gv.vec, v)
    return gv
end

function Base.pop!(gv::GPUSyncStructArray)
    _resync_cpu!(gv)
    return pop!(gv.vec)
end

function Base.sizehint!(gv::GPUSyncStructArray, i::Integer)
    sizehint!(gv.vec, i)
    return gv
end

function Base.copyto!(gv::GPUSyncStructArray, doffs::Integer, src::AbstractVector, soffs::Integer, n::Integer)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    copyto!(gv.vec, doffs, src, soffs, n)
    return gv
end

function Base.similar(gv::GPUSyncStructArray{T,BT}, ::Type{T}, size::Dims{1}) where {T,BT}
    return GPUSyncStructArray{T,BT}(Vector{T}(undef, size), BT(undef, 0), true, true)
end

Base.IndexStyle(::Type{<:GPUSyncStructArray}) = IndexLinear()

function _resync_cpu!(gv::GPUSyncStructArray)
    if !gv.sync_cpu
        copyto!(gv.vec, 1, gv.buffer, 1, length(gv.vec))
        gv.sync_cpu = true
    end
    return
end

function _resync_gpu!(gv::GPUSyncStructArray{T,BT}) where {T,BT}
    if !gv.sync_gpu
        # TODO: maybe consider shrinking if CPU vector is much smaller
        # to save GPU space
        if length(gv.buffer) < length(gv.vec)
            new_cap = max(length(gv.vec), 2 * length(gv.buffer))
            gv.buffer = BT(undef, new_cap)
        end
        copyto!(gv.buffer, 1, gv.vec, 1, length(gv.vec))
        gv.sync_gpu = true
    end
    return
end

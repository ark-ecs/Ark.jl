
mutable struct GPUVector{T,BT} <: AbstractVector{T}
    const vec::Vector{T}
    buffer::BT
    sync_cpu::Bool
    sync_gpu::Bool
end

function GPUVector{T,BT}() where {T,BT}
    return GPUVector{T,BT}(Vector{T}(), BT(undef,0), true, true)
end

function Ark._storage_type(::Type{Storage{GPUVector{T}}}, ::Type{C}) where {T,C}
    GPUVector{C,T{C}}
end

Base.size(s::GPUVector) = (length(s.vec),)

function gpuview(s::FieldViewable{<:Any, 1, <:GPUVector}; readonly::Bool=false)
    return gpuview(parent(s); readonly=readonly)
end

function gpuview(s::GPUVector; readonly::Bool=false)
    _resync_gpu!(s)
    if !readonly
        s.sync_cpu = false
    end
    return view(s.buffer, 1:length(s.vec))
end

Base.@propagate_inbounds function Base.getindex(s::GPUVector, i::Int)
    _resync_cpu!(s)
    return s.vec[i]
end

Base.@propagate_inbounds function Base.setindex!(s::GPUVector, v, i::Int)
    _resync_cpu!(s) 
    s.sync_gpu = false 
    s.vec[i] = v
    return v
end

function Base.resize!(s::GPUVector, new_len::Integer)
    _resync_cpu!(s)
    s.sync_gpu = false
    resize!(s.vec, new_len)
    return s
end

function Base.empty!(s::GPUVector)
    s.sync_gpu = false
    empty!(s.vec)
    return s
end

function Base.push!(s::GPUVector, v)
    _resync_cpu!(s)
    s.sync_gpu = false
    push!(s.vec, v)
    return s
end

function Base.pop!(s::GPUVector)
    _resync_cpu!(s) 
    return pop!(s.vec)
end

function Base.sizehint!(s::GPUVector, i::Integer)
    sizehint!(s.vec, i)
    return s
end

Base.IndexStyle(::Type{<:GPUVector}) = IndexLinear()

function _resync_cpu!(s::GPUVector)
    if !s.sync_cpu
        copyto!(s.vec, 1, s.buffer, 1, length(s.vec))
        s.sync_cpu = true
    end
    return
end

function _resync_gpu!(s::GPUVector{T,BT}) where {T,BT}
    if !s.sync_gpu
        if length(s.buffer) < length(s.vec)
            new_cap = max(length(s.vec), 2 * length(s.buffer))
            s.buffer = BT(undef, new_cap)
        end
        copyto!(s.buffer, 1, s.vec, 1, length(s.vec))
        s.sync_gpu = true
    end
    return
end


const GPUSyncTypes = Union{GPUSyncVector, GPUSyncStructArray}

Base.size(gv::GPUSyncTypes) = (length(gv.vec),)

Base.@propagate_inbounds function Base.getindex(gv::GPUSyncTypes, i::Int)
    _resync_cpu!(gv)
    return gv.vec[i]
end

Base.@propagate_inbounds function Base.setindex!(gv::GPUSyncTypes, v, i::Int)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    gv.vec[i] = v
    return v
end

function Base.resize!(gv::GPUSyncTypes, new_len::Integer)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    resize!(gv.vec, new_len)
    return gv
end

function Base.empty!(gv::GPUSyncTypes)
    gv.sync_gpu = false
    empty!(gv.vec)
    return gv
end

function Base.push!(gv::GPUSyncTypes, v)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    push!(gv.vec, v)
    return gv
end

function Base.pop!(gv::GPUSyncTypes)
    _resync_cpu!(gv)
    return pop!(gv.vec)
end

function Base.sizehint!(gv::GPUSyncTypes, i::Integer)
    sizehint!(gv.vec, i)
    return gv
end

Base.IndexStyle(::Type{<:GPUSyncTypes}) = IndexLinear()

function _resync_cpu!(gv::GPUSyncTypes)
    if !gv.sync_cpu
        copyto!(gv.vec, 1, gv.buffer, 1, length(gv.vec))
        gv.sync_cpu = true
    end
    return
end

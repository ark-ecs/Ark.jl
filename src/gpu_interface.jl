
const _GPUSyncTypes = Union{GPUSyncVector,GPUSyncStructArray}

Base.size(gv::_GPUSyncTypes) = (length(gv.vec),)

Base.@propagate_inbounds function Base.getindex(gv::_GPUSyncTypes, i::Int)
    _resync_cpu!(gv)
    return gv.vec[i]
end

Base.@propagate_inbounds function Base.setindex!(gv::_GPUSyncTypes, v, i::Int)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    gv.vec[i] = v
    return v
end

function Base.resize!(gv::_GPUSyncTypes, new_len::Integer)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    resize!(gv.vec, new_len)
    return gv
end

function Base.empty!(gv::_GPUSyncTypes)
    gv.sync_gpu = false
    empty!(gv.vec)
    return gv
end

function Base.push!(gv::_GPUSyncTypes, v)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    push!(gv.vec, v)
    return gv
end

function Base.pop!(gv::_GPUSyncTypes)
    _resync_cpu!(gv)
    return pop!(gv.vec)
end

function Base.sizehint!(gv::_GPUSyncTypes, i::Integer)
    sizehint!(gv.vec, i)
    return gv
end

Base.IndexStyle(::Type{<:_GPUSyncTypes}) = IndexLinear()

function _resync_cpu!(gv::_GPUSyncTypes)
    if !gv.sync_cpu
        copyto!(gv.vec, 1, gv.buffer, 1, length(gv.vec))
        gv.sync_cpu = true
    end
    return
end

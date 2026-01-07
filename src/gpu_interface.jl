
const _GPUSyncTypes = Union{GPUSyncVector,GPUSyncStructArray}

Base.size(gv::_GPUSyncTypes) = (length(getfield(gv, :vec)),)

Base.@propagate_inbounds function Base.getindex(gv::_GPUSyncTypes, i::Int)
    _resync_cpu!(gv)
    return getfield(gv, :vec)[i]
end

Base.@propagate_inbounds function Base.setindex!(gv::_GPUSyncTypes, v, i::Int)
    _resync_cpu!(gv)
    setfield!(gv, :sync_gpu, false)
    getfield(gv, :vec)[i] = v
    return v
end

function Base.resize!(gv::_GPUSyncTypes, new_len::Integer)
    _resync_cpu!(gv)
    setfield!(gv, :sync_gpu, false)
    resize!(getfield(gv, :vec), new_len)
    return gv
end

function Base.empty!(gv::_GPUSyncTypes)
    setfield!(gv, :sync_gpu, false)
    empty!(getfield(gv, :vec))
    return gv
end

function Base.push!(gv::_GPUSyncTypes, v)
    _resync_cpu!(gv)
    setfield!(gv, :sync_gpu, false)
    push!(getfield(gv, :vec), v)
    return gv
end

function Base.pop!(gv::_GPUSyncTypes)
    _resync_cpu!(gv)
    return pop!(getfield(gv, :vec))
end

function Base.sizehint!(gv::_GPUSyncTypes, i::Integer)
    sizehint!(getfield(gv, :vec), i)
    return gv
end

Base.IndexStyle(::Type{<:_GPUSyncTypes}) = IndexLinear()

function _resync_cpu!(gv::_GPUSyncTypes)
    if !getfield(gv, :sync_cpu)
        vec = getfield(gv, :vec)
        buffer = getfield(gv, :buffer)
        copyto!(vec, 1, buffer, 1, length(vec))
        setfield!(gv, :sync_cpu, true)
    end
    return
end


struct _EntityPool
    gens::Vector{UInt32}   # slot k = current generation (all slots)
    free::Vector{UInt32}   # stack of free ids (free slots only)
end

function _EntityPool(cap::UInt32)
    gens = UInt32[typemax(UInt32)]
    sizehint!(gens, cap)

    return _EntityPool(gens, UInt32[])
end

function _get_entity(p::_EntityPool)::Entity
    if isempty(p.free)
        return _get_new_entity(p)
    end
    id = pop!(p.free)
    @inbounds gen = p.gens[id % Int]
    return _Entity(id, gen)
end

function _get_new_entity(p::_EntityPool)::Entity
    e = _new_entity(length(p.gens) + 1, 0)
    push!(p.gens, UInt32(0))
    return e
end

function _get_pending_entity(p::_EntityPool)::Entity
    entity = _get_entity(p)
    return _new_entity(entity._id, entity._gen + UInt32(1))
end

function _activate_entity!(p::_EntityPool, e::Entity)
    @inbounds p.gens[e._id % Int] = e._gen
    return nothing
end

function _get_new_entities!(p::_EntityPool, n::Integer)
    old_len = length(p.gens)
    new_len = old_len + n
    resize!(p.gens, new_len)
    for i in (old_len+1):new_len
        @inbounds p.gens[i] = UInt32(0)
    end
    return
end

function _recycle(p::_EntityPool, e::Entity)
    if e._id < 2
        throw(ArgumentError("can't recycle the reserved zero entity"))
    end
    push!(p.free, e._id)
    @inbounds p.gens[e._id % Int] = e._gen + UInt32(1)
    return nothing
end

function _is_alive(p::_EntityPool, e::Entity)::Bool
    @inbounds return e._gen == p.gens[e._id % Int]
end

function _reset!(p::_EntityPool)
    resize!(p.gens, 1)
    empty!(p.free)
    return
end

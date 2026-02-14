
mutable struct _EntityPool
    const entities::Vector{Entity}
    next::Int
end

function _EntityPool(cap::UInt32)
    v = [_new_entity(UInt32(0), typemax(UInt32))]
    sizehint!(v, cap)

    return _EntityPool(v, 0)
end

function _get_entity(p::_EntityPool)::Entity
    if p.next == 0
        return _get_new_entity(p)
    end
    curr = p.next
    temp = p.entities[curr]

    p.next = temp._id
    entity = _Entity(curr % UInt32, temp._gen)
    p.entities[curr] = entity

    return entity
end

function _get_new_entity(p::_EntityPool)::Entity
    e = _new_entity(length(p.entities) + 1, 0)
    push!(p.entities, e)
    return e
end

function _recycle(p::_EntityPool, e::Entity)
    if e._id < 2
        throw(ArgumentError("can't recycle the reserved zero entity"))
    end
    temp = p.next
    p.next = e._id
    p.entities[e._id] = _new_entity(temp % UInt32, e._gen + UInt32(1))
    return nothing
end

function _is_alive(p::_EntityPool, e::Entity)::Bool
    @inbounds return e._gen == p.entities[e._id]._gen
end

function _reset!(p::_EntityPool)
    resize!(p.entities, 1)
    p.next = 0
end

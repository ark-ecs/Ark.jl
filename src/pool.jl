
# Manages entity liveness and id recycling on the shared entity records
# vector (aliased by `_WorldState._entities`). The pool owns the `gen` field
# and the free list threaded through the `row` field of dead records;
# locations are written by `_place_entity!` and friends.
mutable struct _EntityPool
    const entities::Vector{_EntityIndex}
    next::Int
end

function _EntityPool(cap::UInt32)
    v = [_EntityIndex(typemax(UInt32), UInt32(0), typemax(UInt32), UInt32(0))]
    sizehint!(v, cap)

    return _EntityPool(v, 0)
end

function _get_entity(p::_EntityPool)::Entity
    if p.next == 0
        return _get_new_entity(p)
    end
    curr = p.next
    index = p.entities[curr]

    p.next = index.row % Int

    return _Entity(curr % UInt32, index.gen)
end

function _get_new_entity(p::_EntityPool)::Entity
    id = length(p.entities) + 1
    push!(p.entities, _EntityIndex(UInt32(0), UInt32(0), UInt32(0), UInt32(0)))
    return _new_entity(id, 0)
end

function _get_pending_entity(p::_EntityPool)::Entity
    entity = _get_entity(p)
    return _new_entity(entity._id, entity._gen + UInt32(1))
end

# Appends `n` uninitialized records; the caller must fully initialize them.
function _grow_entities!(p::_EntityPool, n::Integer)
    resize!(p.entities, length(p.entities) + n)
    return
end

function _recycle(p::_EntityPool, e::Entity)
    if e._id < 2
        throw(ArgumentError("can't recycle the reserved zero entity"))
    end
    temp = p.next
    p.next = e._id
    p.entities[e._id] = _EntityIndex(UInt32(0), temp % UInt32, e._gen + UInt32(1), UInt32(0))
    return nothing
end

function _is_alive(p::_EntityPool, e::Entity)::Bool
    @inbounds return e._gen == p.entities[e._id].gen
end

function _reset!(p::_EntityPool)
    resize!(p.entities, 1)
    p.next = 0
end

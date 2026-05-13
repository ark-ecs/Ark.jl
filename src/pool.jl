
mutable struct _EntityPool
    const ids::Vector{UInt32}
    const gens::Vector{UInt32}
    next::Int
end

function _EntityPool(cap::UInt32)
    v1 = [UInt32(0)]
    sizehint!(v1, cap)
    v2 = [typemax(UInt32)]
    sizehint!(v2, cap)

    return _EntityPool(v1, v2, 0)
end

@inbounds function _get_entity(p::_EntityPool)::Entity
    if p.next == 0
        return _get_new_entity(p)
    end
    curr = p.next
    temp_id = p.ids[curr]
    temp_gen = p.gens[curr]

    p.next = temp_id
    id = curr % UInt32
    p.ids[curr] = id
    p.gens[curr] = temp_gen

    return _Entity(id, temp_gen)
end

function _get_new_entity(p::_EntityPool)::Entity
    id = (length(p.ids) + 1) % UInt32
    push!(p.ids, id)
    push!(p.gens, UInt32(0))
    return _new_entity(id, UInt32(0))
end

function _get_new_entities!(p::_EntityPool, n::Integer)
    old_len = length(p.ids)
    new_len = old_len + n
    resize!(p.ids, new_len)
    resize!(p.gens, new_len)
    @inbounds for i in (old_len+1):new_len
        p.ids[i] = i % UInt32
        p.gens[i] = UInt32(0)
    end
    return
end

@inbounds function _recycle(p::_EntityPool, e::Entity)
    if e._id < 2
        throw(ArgumentError("can't recycle the reserved zero entity"))
    end
    temp = p.next
    p.next = e._id

    p.ids[e._id] = temp % UInt32
    p.gens[e._id] = e._gen + UInt32(1)
    return nothing
end

function _is_alive(p::_EntityPool, e::Entity)::Bool
    @inbounds return e._gen == p.gens[e._id]
end

function _reset!(p::_EntityPool)
    resize!(p.ids, 1)
    resize!(p.gens, 1)
    p.next = 0
end

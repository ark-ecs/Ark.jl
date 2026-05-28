
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

function _get_new_entities!(p::_EntityPool, n::Integer)
    old_len = length(p.entities)
    new_len = old_len + n
    resize!(p.entities, new_len)
    for i in (old_len+1):new_len
        @inbounds p.entities[i] = _new_entity(i % UInt32, UInt32(0))
    end
    return
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

struct _QueryHandle
    _id::UInt32
    _gen::UInt64
end

mutable struct _QueryPool
    const queries::Vector{_QueryHandle}
    next::UInt32
    const _lock::ReentrantLock
end

function _QueryPool(cap::UInt32=UInt32(16))
    queries = Vector{_QueryHandle}()
    sizehint!(queries, cap)

    return _QueryPool(queries, UInt32(0), ReentrantLock())
end

function _get_query(p::_QueryPool)::_QueryHandle
    lock(p._lock)
    try
        return _get_query_unlocked(p)
    finally
        unlock(p._lock)
    end
end

function _get_query_unlocked(p::_QueryPool)::_QueryHandle
    if p.next == 0
        return _get_new_query_unlocked(p)
    end

    curr = p.next
    temp = p.queries[curr]

    p.next = temp._id
    query = _QueryHandle(curr, temp._gen)
    p.queries[curr] = query

    return query
end

function _get_new_query(p::_QueryPool)::_QueryHandle
    lock(p._lock)
    try
        return _get_new_query_unlocked(p)
    finally
        unlock(p._lock)
    end
end

function _get_new_query_unlocked(p::_QueryPool)::_QueryHandle
    query = _QueryHandle(UInt32(length(p.queries) + 1), UInt64(0))
    push!(p.queries, query)
    return query
end

function _recycle(p::_QueryPool, query::_QueryHandle)::Bool
    lock(p._lock)
    try
        if !_is_alive_unlocked(p, query)
            return false
        end

        temp = p.next
        p.next = query._id
        p.queries[query._id] = _QueryHandle(temp, query._gen + UInt64(1))

        return true
    finally
        unlock(p._lock)
    end
end

function _is_alive(p::_QueryPool, query::_QueryHandle)::Bool
    lock(p._lock)
    try
        return _is_alive_unlocked(p, query)
    finally
        unlock(p._lock)
    end
end

function _is_alive_unlocked(p::_QueryPool, query::_QueryHandle)::Bool
    id = query._id
    if id == 0 || id > length(p.queries)
        return false
    end

    @inbounds active_query = p.queries[id]
    return active_query._id == id && active_query._gen == query._gen
end

function _reset!(p::_QueryPool)
    lock(p._lock)
    try
        empty!(p.queries)
        p.next = UInt32(0)
    finally
        unlock(p._lock)
    end
end

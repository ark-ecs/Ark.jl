
struct _IdCollection
    ids::Vector{UInt32}
    indices::Dict{UInt32,Int}
end

function _IdCollection()
    return _IdCollection(Vector{UInt32}(), Dict{UInt32,Int}())
end

function _IdCollection(ids::UInt32...)
    vec = collect(UInt32, ids)
    indices = Dict{UInt32,Int}()

    for (i, id) in enumerate(ids)
        indices[id] = i
    end

    return _IdCollection(vec, indices)
end

function _add_id!(ids::_IdCollection, id::UInt32)
    push!(ids.ids, id)
    ids.indices[id] = length(ids.ids)
    return nothing
end

function _remove_id!(ids::_IdCollection, id::UInt32)
    if !haskey(ids.indices, id)
        return false
    end
    idx = ids.indices[id]
    last = length(ids.ids)
    if idx != last
        ids.ids[idx], ids.ids[last] = ids.ids[last], ids.ids[idx]
        ids.indices[ids.ids[idx]] = idx
    end
    pop!(ids.ids)
    delete!(ids.indices, id)
    return true
end

function _contains(ids::_IdCollection, id::UInt32)
    return haskey(ids.indices, id)
end

function _clear!(ids::_IdCollection)
    empty!(ids.ids)
    empty!(ids.indices)
    return nothing
end

Base.length(t::_IdCollection) = length(t.ids)
Base.isempty(t::_IdCollection) = isempty(t.ids)
Base.@propagate_inbounds Base.getindex(t::_IdCollection, i::Int) = t.ids[i]

const _empty_tables::Vector{UInt32} = Vector{UInt32}()
const _empty_table_ids::_IdCollection = _IdCollection()

"""
    Entity

[Entity](@ref Entities) identifier.

Entities can be constructed using a [World](@ref) via [new_entity!](@ref) and [new_entities!](@ref).

Entities can be safely stored in [components](@ref Components) and [resources](@ref Resources).
"""
struct Entity
    _id::UInt32
    _gen::UInt32

    _Entity(id::UInt32, gen::UInt32) = new(id, gen)
end

"""
    is_zero(entity::Entity)::Bool

Returns whether an [Entity](@ref) is the reserved [zero_entity](@ref).
"""
function is_zero(entity::Entity)::Bool
    return entity._id == 1
end

function _new_entity(id::UInt32, gen::UInt32)
    _Entity(id, gen)
end

function _new_entity(id::Int, gen::Int)
    _Entity(UInt32(id), UInt32(gen))
end

function Base.show(io::IO, entity::Entity)
    print(io, "Entity($(Int(entity._id)), $(Int(entity._gen)))")
end

struct _EntityIndex
    table::UInt32
    row::UInt32
end

"""
    Entities

Archetype column for entities. Can be iterated and indexed like a Vector, but is read-only.

Used in [query iteration](@ref Queries) and [batch operations](@ref "Batch operations") callbacks.
"""
struct Entities <: AbstractVector{Entity}
    _data::Vector{Entity}
    function Entities(cap::Int)
        vec = Vector{Entity}()
        if cap > 0
            sizehint!(vec, cap)
        end
        new(vec)
    end
end

function _new_entities_column()
    Entities(1024)
end

Base.@propagate_inbounds function Base.getindex(c::Entities, i::Integer)
    getindex(c._data, i)
end
Base.length(c::Entities) = length(c._data)
Base.eachindex(c::Entities) = eachindex(c._data)
Base.enumerate(c::Entities) = enumerate(c._data)
Base.iterate(c::Entities) = iterate(c._data)
Base.iterate(c::Entities, state) = iterate(c._data, state)
Base.eltype(::Type{Entities}) = Entity
Base.IndexStyle(::Type{Entities}) = IndexLinear()
Base.size(c::Entities) = (length(c),)
Base.firstindex(c::Entities) = firstindex(c._data)
Base.lastindex(c::Entities) = lastindex(c._data)

function Base.show(io::IO, e::Entities)
    if length(e) < 12
        elems = join(e, ", ")
        print(io, "Entities[$elems]")
    else
        first = join(e[1:5], ", ")
        last = join(e[(end-4):end], ", ")
        print(io, "Entities[$first, …, $last]")
    end
end

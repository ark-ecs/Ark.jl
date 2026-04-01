
"""
    EntityHandle{W<:World}

A handle to an [`Entity`](@ref) within a specific [`World`](@ref),
allowing for dict-like component and relationship access.

Created by indexing a world with an entity i.e. `we = world[entity]`.

# Examples

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
we = world[entity]

# Get components
pos = we[Position]
pos, vel = we[(Position, Velocity)]

# Set components
we[Position] = Position(0, 0)
we[(Position, Velocity)] = (Position(0, 0), Velocity(1,1))

# Check components
has_pos = Position in we
has_pos_vel = (Position, Velocity) in we

# Relationships
we.rel[ChildOf] = parent_entity
parent_entity = we.rel[ChildOf]

# output

```
"""
struct EntityHandle{W<:World}
	world::W
	entity::Entity
end

struct _EntityHandleRel{W<:World}
	world::W
	entity::Entity
end

Base.getindex(world::World, entity::Entity) = EntityHandle(world, entity)

function Base.getindex(entityhandle::EntityHandle, comp::Type)
    return get_components(entityhandle.world, entityhandle.entity, (comp,))[1]
end

function Base.getindex(entityhandle::EntityHandle, comps::Tuple{Vararg{Type}})
    return get_components(entityhandle.world, entityhandle.entity, comps)
end

function Base.setindex!(entityhandle::EntityHandle, value, comp::Type)
    set_components!(entityhandle.world, entityhandle.entity, (value,))[1]
end

function Base.setindex!(entityhandle::EntityHandle, values::Tuple, comps::Tuple{Vararg{Type}})
    set_components!(entityhandle.world, entityhandle.entity, values)
end

function Base.in(comp::Type, entityhandle::EntityHandle)
    return has_components(entityhandle.world, entityhandle.entity, (comp,))
end

function Base.in(comps::Tuple{Vararg{Type}}, entityhandle::EntityHandle)
    return has_components(entityhandle.world, entityhandle.entity, comps)
end

function _unchecked_getindex(entityhandle::EntityHandle, comp::Type)
    return get_components(entityhandle.world, entityhandle.entity, (comp,); _unchecked=true)[1]
end

function _unchecked_getindex(entityhandle::EntityHandle, comps::Tuple{Vararg{Type}})
    return get_components(entityhandle.world, entityhandle.entity, comps; _unchecked=true)
end

function _unchecked_setindex!(entityhandle::EntityHandle, value, comp::Type)
    set_components!(entityhandle.world, entityhandle.entity, (value,); _unchecked=true)
end

function _unchecked_setindex!(entityhandle::EntityHandle, values::Tuple, comps::Tuple{Vararg{Type}})
    set_components!(entityhandle.world, entityhandle.entity, values; _unchecked=true)
end

function _unchecked_in(comp::Type, entityhandle::EntityHandle)
    return has_components(entityhandle.world, entityhandle.entity, (comp,); _unchecked=true)
end

function _unchecked_in(comps::Tuple{Vararg{Type}}, entityhandle::EntityHandle)
    return has_components(entityhandle.world, entityhandle.entity, comps; _unchecked=true)
end

function add_components!(
    entityhandle::EntityHandle,
    values::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
    _unchecked::Bool=false,
)
	world = entityhandle.world
	entity = entityhandle.entity
    return add_components!(world, entity, values; relations, _unchecked)
end

function remove_components!(
	entityhandle::EntityHandle,
    comp_types::Tuple;
    _unchecked::Bool=false,
)
	world = entityhandle.world
	entity = entityhandle.entity
    return remove_components!(world, entity, comp_types; _unchecked)
end

Base.@constprop :aggressive function Base.getproperty(entityhandle::EntityHandle, name::Symbol)
    if name === :rel
        return _EntityHandleRel(getfield(entityhandle, :world), getfield(entityhandle, :entity))
    end
    return getfield(entityhandle, name)
end

function Base.getindex(entityhandle::_EntityHandleRel, comp::Type)
    return get_relations(entityhandle.world, entityhandle.entity, (comp,))[1]
end

function Base.getindex(entityhandle::_EntityHandleRel, comps::Tuple{Vararg{Type}})
    return get_relations(entityhandle.world, entityhandle.entity, comps)
end

function Base.setindex!(entityhandle::_EntityHandleRel, target::Entity, comp::Type)
    set_relations!(entityhandle.world, entityhandle.entity, (comp => target,))[1]
end

function Base.setindex!(entityhandle::_EntityHandleRel, targets::Tuple{Vararg{Entity}}, comps::Tuple{Vararg{Type}})
    relations = ntuple(i -> comps[i] => targets[i], length(comps))
    set_relations!(entityhandle.world, entityhandle.entity, relations)
end

function _unchecked_getindex(entityhandle::_EntityHandleRel, comp::Type)
    return get_relations(entityhandle.world, entityhandle.entity, (comp,); _unchecked=true)[1]
end

function _unchecked_getindex(entityhandle::_EntityHandleRel, comps::Tuple{Vararg{Type}})
    return get_relations(entityhandle.world, entityhandle.entity, comps; _unchecked=true)
end

function _unchecked_setindex!(entityhandle::_EntityHandleRel, target::Entity, comp::Type)
    set_relations!(entityhandle.world, entityhandle.entity, (comp => target,); _unchecked=true)[1]
end

function _unchecked_setindex!(entityhandle::_EntityHandleRel, targets::Tuple{Vararg{Entity}}, comps::Tuple{Vararg{Type}})
    relations = ntuple(i -> comps[i] => targets[i], length(comps))
    set_relations!(entityhandle.world, entityhandle.entity, relations; _unchecked=true)
end

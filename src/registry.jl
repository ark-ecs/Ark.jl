
mutable struct _ComponentRegistry
    counter::Int
    const components::Dict{DataType,Int}
    const types::Vector{DataType}
    const is_relation::Vector{Bool}
end

function _ComponentRegistry()
    _ComponentRegistry(0x01, Dict{DataType,Int}(), Vector{DataType}(), Vector{Bool}())
end

@inline function _get_id!(registry::_ComponentRegistry, ::Type{C})::Int where C
    return get(registry.components, C) do
        throw(ArgumentError(lazy"component type $C is not registered"))
    end
end

@inline function _is_relation(registry::_ComponentRegistry, comp_id::Int)::Bool
    return registry.is_relation[comp_id]
end

function _register_component!(registry::_ComponentRegistry, ::Type{C})::Int where C
    if haskey(registry.components, C)
        throw(ArgumentError(lazy"duplicate component type $C during world creation"))
    end
    id = registry.counter
    registry.components[C] = id
    push!(registry.types, C)
    push!(registry.is_relation, C <: Relationship)
    registry.counter += 1
    return id
end

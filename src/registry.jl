
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

# `@nospecialize` on the component type is deliberate: this is called once per component
# type during world construction, and its body only uses `C` as a value (a `Dict` key and
# `push!` argument). Specializing it per type would compile one method instance per
# component for no runtime benefit, which dominates world-construction compile time for
# worlds with many component types.
function _register_component!(registry::_ComponentRegistry, @nospecialize(C::DataType), is_relation::Bool)::Int
    if haskey(registry.components, C)
        throw(ArgumentError(lazy"duplicate component type $C during world creation"))
    end
    id = registry.counter
    registry.components[C] = id
    push!(registry.types, C)
    push!(registry.is_relation, is_relation)
    registry.counter += 1
    return id
end

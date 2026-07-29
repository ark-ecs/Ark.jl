
# `components` is an `IdDict` rather than a `Dict` for compile time, not for lookup speed.
# `Dict`'s generic `setindex!`/`getindex` specialize on the key, so storing a component type
# compiles one instance per component type - about 10ms each, which is the single largest
# cost of building a world with a large schema. `IdDict` takes its key `@nospecialize`d, so
# it compiles once for every schema. Identity is also the right equality here: types are
# interned, so `IdDict` and `Dict` cannot disagree on a `DataType` key.
mutable struct _ComponentRegistry
    counter::Int
    const components::IdDict{DataType,Int}
    const types::Vector{DataType}
    const is_relation::Vector{Bool}
end

function _ComponentRegistry()
    _ComponentRegistry(0x01, IdDict{DataType,Int}(), Vector{DataType}(), Vector{Bool}())
end

@inline function _get_id!(registry::_ComponentRegistry, ::Type{C})::Int where C
    return get(registry.components, C) do
        throw(ArgumentError(lazy"component type $C is not registered"))
    end
end

@inline function _is_relation(registry::_ComponentRegistry, comp_id::Int)::Bool
    return registry.is_relation[comp_id]
end

"""
    _register_components!(registry, types::Vector{Any}, relation_indices::Vector{Int})

Registers every component type of a boxed world in one runtime loop.

Same motivation as [_new_storages](@ref): the types are consumed as values, so the caller
does not grow one specialized call per component type.
"""
@noinline function _register_components!(
    registry::_ComponentRegistry,
    types::Vector{Any},
    relation_indices::Vector{Int},
)::Vector{Int}
    ids = Vector{Int}(undef, length(types))
    for i in eachindex(types)
        @inbounds ids[i] = _register_component!(registry, types[i]::DataType, i in relation_indices)
    end
    return ids
end

# `@nospecialize` on the component type is deliberate: this is called once per component
# type during world construction, and its body only uses `C` as a value (a `Dict` key and
# `push!` argument). Specializing it per type would compile one method instance per
# component for no runtime benefit, which dominates world-construction compile time for
# worlds with many component types.
#
# `@noinline` is what makes that stick. Inlining puts the concrete component type back at the
# `Dict` insertion, which then compiles one `setindex!` instance per component type - the very
# cost `@nospecialize` is here to avoid. Measured on a 300 component world, dropping it costs
# 300 extra method instances and about 2.5 seconds of world-construction compile time.
@noinline function _register_component!(registry::_ComponentRegistry, @nospecialize(C::DataType), is_relation::Bool)::Int
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

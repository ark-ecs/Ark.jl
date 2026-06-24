struct _NewEntity{V<:Tuple}
    entity::Entity
    components::V
end

struct _RemoveEntity
    entity::Entity
end

struct _AddComponents{C<:Tuple}
    entity::Entity
    components::C
end

struct _RemoveComponents{R<:Tuple}
    entity::Entity
end

struct _ExchangeComponents{A<:Tuple,R<:Tuple}
    entity::Entity
    add::A
end

struct _SetComponents{V<:Tuple}
    entity::Entity
    values::V
end

struct _SetRelations{R<:Tuple}
    entity::Entity
    relations::R
end

const _Command = Union{
    _NewEntity,
    _RemoveEntity,
    _AddComponents,
    _RemoveComponents,
    _ExchangeComponents,
    _SetComponents,
    _SetRelations,
}

struct CommandBuffer{W<:World,C<:_Command}
    _world::W
    _commands::Vector{C}
end

function _cmd_value_type(T, relation_types::Type{<:Tuple})
    if T isa Type && _is_relation_type(T, relation_types)
        return Pair{T,Entity}
    end
    return T
end

function _spec_component_types(::Type{T}) where {T<:Tuple}
    return [_val_parameter(fieldtype(T, i)) for i in 1:fieldcount(T)]
end

function _spec_value_tuple_type(::Type{T}) where {T<:Tuple}
    component_types = _spec_component_types(T)
    return Tuple{component_types...}
end

function _spec_value_tuple_type(
    ::Type{T},
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    relation_types = _schema_relation_types(Storage)
    value_types = [
        _cmd_value_type(component_type, relation_types) for component_type in _spec_component_types(T)
    ]
    return Tuple{value_types...}
end

function _spec_relations_tuple_type(::Type{T}) where {T<:Tuple}
    relation_types = fill(Pair{DataType,Entity}, fieldcount(T))
    return Tuple{relation_types...}
end

_spec_valtuple_type(spec::Tuple) = typeof(_valtuple(spec))

@generated function _command_type(
    ::Type{T},
    ::typeof(new_entity!),
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    _NewEntity{_spec_value_tuple_type(T, Storage)}
end

@generated function _command_type(
    ::Type{T},
    ::typeof(add_components!),
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    _AddComponents{_spec_value_tuple_type(T, Storage)}
end

@generated function _command_type(::Type{T}, ::typeof(remove_components!)) where {T<:Tuple}
    _RemoveComponents{_spec_value_tuple_type(T)}
end

@generated function _command_type(
    ::Type{T},
    ::typeof(exchange_components!),
    ::Type{U},
    ::Type{Storage},
) where {T<:Tuple,U<:Tuple,Storage<:_WorldStorage}
    _ExchangeComponents{_spec_value_tuple_type(T, Storage),_spec_value_tuple_type(U)}
end

@generated function _command_type(::Type{T}, ::typeof(set_components!)) where {T<:Tuple}
    _SetComponents{_spec_value_tuple_type(T)}
end

@generated function _command_type(::Type{T}, ::typeof(set_relations!)) where {T<:Tuple}
    _SetRelations{_spec_relations_tuple_type(T)}
end

function _exchange_spec_components(spec::Tuple)
    if length(spec) != 2 || !(spec[2] isa NamedTuple) ||
       !hasproperty(spec[2], :add) || !hasproperty(spec[2], :remove)
        throw(
            ArgumentError(
                "exchange_components! command spec must be (exchange_components!, (add=(...), remove=(...)))",
            ),
        )
    end
    add = spec[2].add
    remove = spec[2].remove
    if !(add isa Tuple) || !(remove isa Tuple)
        throw(ArgumentError("exchange_components! command spec add and remove fields must be tuples"))
    end
    return add, remove
end

function _spec_command_type(::Type{Storage}, spec::Tuple) where {Storage<:_WorldStorage}
    fn = spec[1]
    if fn === new_entity!
        return _command_type(_spec_valtuple_type(spec[2]), new_entity!, Storage)
    elseif fn === remove_entity!
        return _RemoveEntity
    elseif fn === add_components!
        return _command_type(_spec_valtuple_type(spec[2]), add_components!, Storage)
    elseif fn === remove_components!
        return _command_type(_spec_valtuple_type(spec[2]), remove_components!)
    elseif fn === exchange_components!
        add, remove = _exchange_spec_components(spec)
        return _command_type(
            _spec_valtuple_type(add),
            exchange_components!,
            _spec_valtuple_type(remove),
            Storage,
        )
    elseif fn === set_components!
        return _command_type(_spec_valtuple_type(spec[2]), set_components!)
    elseif fn === set_relations!
        return _command_type(_spec_valtuple_type(spec[2]), set_relations!)
    else
        throw(ArgumentError("unknown command function $fn"))
    end
end

function _specs_to_types(world::World, specs::Tuple)
    n = length(specs)
    if n == 0
        throw(ArgumentError("command buffer needs to contain at least one deferred operation"))
    end
    storage_type = typeof(_storage(world))
    types = Vector{DataType}(undef, n)
    for i in 1:n
        types[i] = _spec_command_type(storage_type, specs[i])
    end
    Tuple(types)
end

"""
    CommandBuffer(world::World, specs::Tuple)

Creates a new command buffer for the given [World](@ref)
for staging structural changes to apply later.

The `specs` tuple specifies which operations the buffer supports.
Each element is a tuple of the form `(function, component_types...)`:

```julia
buf = CommandBuffer(
    world,
    (
        (new_entity!, (Position, Velocity)),
        (remove_entity!,),
        (add_components!, (Velocity,)),
        (remove_components!, (Velocity,)),
        (exchange_components!, (add=(Health,), remove=(Velocity,))),
        (set_components!, (Position,)),
        (set_relations!, (ChildOf,)),
    ),
)
```

All recorded commands are stored and executed when `apply!` is called.

See the [manual](@ref "Command buffer") for details and examples.
"""
function CommandBuffer(world::W, specs::Tuple) where W
    cmd_types = _specs_to_types(world, specs)
    C = Union{cmd_types...}
    CommandBuffer{W,C}(world, Vector{C}())
end

function new_entity!(buf::CommandBuffer, values::Tuple)
    world = buf._world
    state = _state(world)
    entity = _reserve_pending_entity!(state)
    _reserve_entity_index!(state, entity)
    push!(buf._commands, _NewEntity(entity, values))
    return entity
end

function remove_entity!(buf::CommandBuffer, entity::Entity)
    push!(buf._commands, _RemoveEntity(entity))
    return nothing
end

function add_components!(buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf._commands, _AddComponents(entity, values))
    return nothing
end

@generated function _make_remove_cmd(entity::Entity, types::T) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    R = Tuple{inner...}
    quote
        _RemoveComponents{$R}(entity)
    end
end

Base.@constprop :aggressive function remove_components!(buf::CommandBuffer, entity::Entity, types::Tuple)
    push!(buf._commands, _make_remove_cmd(entity, _valtuple(types)))
    return nothing
end

@generated function _make_exchange_cmd(
    entity::Entity,
    add::A,
    remove::T,
) where {A<:Tuple,T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    R = Tuple{inner...}
    return quote
        _ExchangeComponents{$A,$R}(entity, add)
    end
end

Base.@constprop :aggressive function exchange_components!(
    buf::CommandBuffer,
    entity::Entity;
    add::Tuple=(),
    remove::Tuple=(),
)
    push!(buf._commands, _make_exchange_cmd(entity, add, _valtuple(remove)))
    return nothing
end

function set_components!(buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf._commands, _SetComponents(entity, values))
    return nothing
end

function set_relations!(buf::CommandBuffer, entity::Entity, relations::Tuple)
    push!(buf._commands, _SetRelations(entity, relations))
    return nothing
end

@inline Base.@constprop :aggressive function _apply_new_entity!(world::World, entity::Entity, values::Tuple)
    values, relations = _normalize_relations(values, Val(:value))
    rel_types, targets = _relation_types_and_targets(relations)
    world_state = _state(world)
    world_storage = _storage(world)
    _, table_id = _new_entity!(world_state, world_storage, entity,
        Val{typeof(values)}(), values, rel_types, targets, Val(false))
    _fire_new_entity_events!(world_state, entity, table_id, relations)
    return nothing
end

"""
    apply!(buf::CommandBuffer)

Executes all commands recorded in the buffer in FIFO order.

After execution the command buffer is cleared and can be reused.
"""
@generated function apply!(buf::CommandBuffer{W,C}) where {W,C}
    member_types = C isa Union ? Base.uniontypes(C) : (C,)

    chain = nothing
    for (i, T) in enumerate(member_types)
        body = if T <: _NewEntity
            :(_apply_new_entity!(buf._world, cmd.entity, cmd.components))
        elseif T <: _RemoveEntity
            :(Ark.remove_entity!(buf._world, cmd.entity))
        elseif T <: _AddComponents
            :(Ark.add_components!(buf._world, cmd.entity, cmd.components))
        elseif T <: _RemoveComponents
            R = T.parameters[1]
            types = [fieldtype(R, i) for i in 1:fieldcount(R)]
            :(Ark.remove_components!(buf._world, cmd.entity, $(Expr(:tuple, types...))))
        elseif T <: _ExchangeComponents
            R = T.parameters[2]
            types = [fieldtype(R, i) for i in 1:fieldcount(R)]
            :(Ark.exchange_components!(buf._world, cmd.entity; add=cmd.add,
                remove=($(Expr(:tuple, types...)))))
        elseif T <: _SetComponents
            :(Ark.set_components!(buf._world, cmd.entity, cmd.values))
        elseif T <: _SetRelations
            :(Ark.set_relations!(buf._world, cmd.entity, cmd.relations))
        end

        if i == 1
            chain = body
        else
            cond = :(cmd isa $T)
            chain = Expr(:if, cond, body, chain)
        end
    end

    return quote
        for cmd in buf._commands
            $chain
        end
        empty!(buf._commands)
        return buf
    end
end

"""
    NewEntityCommand(component_types)

Command-buffer spec for [`new_entity!`](@ref).
"""
struct NewEntityCommand{T<:Tuple}
    entity::Entity
    components::T
end

NewEntityCommand(component_types::Tuple) =
    NewEntityCommand{_spec_valtuple_type(component_types)}

"""
    RemoveEntityCommand()

Command-buffer spec for [`remove_entity!`](@ref).
"""
struct RemoveEntityCommand
    entity::Entity
end

RemoveEntityCommand() = RemoveEntityCommand

"""
    AddComponentsCommand(component_types)

Command-buffer spec for [`add_components!`](@ref).
"""
struct AddComponentsCommand{T<:Tuple}
    entity::Entity
    components::T
end

AddComponentsCommand(component_types::Tuple) =
    AddComponentsCommand{_spec_valtuple_type(component_types)}

"""
    RemoveComponentsCommand(component_types)

Command-buffer spec for [`remove_components!`](@ref).
"""
struct RemoveComponentsCommand{T<:Tuple}
    entity::Entity
    components::T
end

RemoveComponentsCommand(component_types::Tuple) =
    RemoveComponentsCommand{_spec_valtuple_type(component_types)}

"""
    ExchangeComponentsCommand(; add=(), remove=())

Command-buffer spec for [`exchange_components!`](@ref).
"""
struct ExchangeComponentsCommand{A<:Tuple,R<:Tuple}
    entity::Entity
    add::A
    remove::R
end

function ExchangeComponentsCommand(; add=(), remove=())
    if !(add isa Tuple) || !(remove isa Tuple)
        throw(ArgumentError("ExchangeComponentsCommand add and remove arguments must be tuples"))
    end
    return ExchangeComponentsCommand{_spec_valtuple_type(add),_spec_valtuple_type(remove)}
end

"""
    SetComponentsCommand(component_types)

Command-buffer spec for [`set_components!`](@ref).
"""
struct SetComponentsCommand{T<:Tuple}
    entity::Entity
    components::T
end

SetComponentsCommand(component_types::Tuple) =
    SetComponentsCommand{_spec_valtuple_type(component_types)}

"""
    SetRelationsCommand(relation_types)

Command-buffer spec for [`set_relations!`](@ref).
"""
struct SetRelationsCommand{T<:Tuple}
    entity::Entity
    relations::T
end

SetRelationsCommand(relation_types::Tuple) =
    SetRelationsCommand{_spec_valtuple_type(relation_types)}

struct CommandBuffer{W<:World,C}
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
    ::Type{NewEntityCommand},
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    NewEntityCommand{_spec_value_tuple_type(T, Storage)}
end

@generated function _command_type(
    ::Type{T},
    ::Type{AddComponentsCommand},
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    AddComponentsCommand{_spec_value_tuple_type(T, Storage)}
end

@generated function _command_type(::Type{T}, ::Type{RemoveComponentsCommand}) where {T<:Tuple}
    RemoveComponentsCommand{T}
end

@generated function _command_type(
    ::Type{T},
    ::Type{ExchangeComponentsCommand},
    ::Type{U},
    ::Type{Storage},
) where {T<:Tuple,U<:Tuple,Storage<:_WorldStorage}
    ExchangeComponentsCommand{_spec_value_tuple_type(T, Storage),U}
end

@generated function _command_type(::Type{T}, ::Type{SetComponentsCommand}) where {T<:Tuple}
    SetComponentsCommand{_spec_value_tuple_type(T)}
end

@generated function _command_type(::Type{T}, ::Type{SetRelationsCommand}) where {T<:Tuple}
    SetRelationsCommand{_spec_relations_tuple_type(T)}
end

function _spec_command_type(
    ::Type{Storage},
    ::Type{NewEntityCommand{T}},
) where {Storage<:_WorldStorage,T<:Tuple}
    return _command_type(T, NewEntityCommand, Storage)
end

_spec_command_type(::Type{Storage}, ::Type{RemoveEntityCommand}) where {Storage<:_WorldStorage} =
    RemoveEntityCommand

function _spec_command_type(
    ::Type{Storage},
    ::Type{AddComponentsCommand{T}},
) where {Storage<:_WorldStorage,T<:Tuple}
    return _command_type(T, AddComponentsCommand, Storage)
end

function _spec_command_type(
    ::Type{Storage},
    ::Type{RemoveComponentsCommand{T}},
) where {Storage<:_WorldStorage,T<:Tuple}
    return _command_type(T, RemoveComponentsCommand)
end

function _spec_command_type(
    ::Type{Storage},
    ::Type{ExchangeComponentsCommand{A,R}},
) where {Storage<:_WorldStorage,A<:Tuple,R<:Tuple}
    return _command_type(
        A,
        ExchangeComponentsCommand,
        R,
        Storage,
    )
end

function _spec_command_type(
    ::Type{Storage},
    ::Type{SetComponentsCommand{T}},
) where {Storage<:_WorldStorage,T<:Tuple}
    return _command_type(T, SetComponentsCommand)
end

function _spec_command_type(
    ::Type{Storage},
    ::Type{SetRelationsCommand{T}},
) where {Storage<:_WorldStorage,T<:Tuple}
    return _command_type(T, SetRelationsCommand)
end

_spec_command_type(::Type{Storage}, command_type::Type) where {Storage<:_WorldStorage} = command_type

function _spec_command_type(::Type{Storage}, spec) where {Storage<:_WorldStorage}
    throw(ArgumentError("unknown command spec $spec"))
end

function _specs_to_types(world::World, specs::Tuple)
    n = length(specs)
    if n == 0
        throw(ArgumentError("command buffer needs to contain at least one deferred operation"))
    end
    storage_type = typeof(_storage(world))
    types = Vector{Any}(undef, n)
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
Built-in world operations are specified with command spec constructors that return command types.
Arbitrary command types can also be included and later recorded with [`record!`](@ref):

```julia
buf = CommandBuffer(
    world,
    (
        NewEntityCommand((Position, Velocity)),
        RemoveEntityCommand(),
        AddComponentsCommand((Velocity,)),
        RemoveComponentsCommand((Velocity,)),
        ExchangeComponentsCommand(add=(Health,), remove=(Velocity,)),
        SetComponentsCommand((Position,)),
        SetRelationsCommand((ChildOf,)),
        ExternalCommand,
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
    push!(buf._commands, NewEntityCommand(entity, values))
    return entity
end

function remove_entity!(buf::CommandBuffer, entity::Entity)
    push!(buf._commands, RemoveEntityCommand(entity))
    return nothing
end

function add_components!(buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf._commands, AddComponentsCommand(entity, values))
    return nothing
end

@inline function _make_remove_cmd(entity::Entity, types::Tuple)
    return RemoveComponentsCommand(entity, types)
end

Base.@constprop :aggressive function remove_components!(buf::CommandBuffer, entity::Entity, types::Tuple)
    push!(buf._commands, _make_remove_cmd(entity, _valtuple(types)))
    return nothing
end

@inline function _make_exchange_cmd(
    entity::Entity,
    add::Tuple,
    remove::Tuple,
)
    return ExchangeComponentsCommand(entity, add, remove)
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
    push!(buf._commands, SetComponentsCommand(entity, values))
    return nothing
end

function set_relations!(buf::CommandBuffer, entity::Entity, relations::Tuple)
    push!(buf._commands, SetRelationsCommand(entity, relations))
    return nothing
end

"""
    record!(buf::CommandBuffer, command)

Records an arbitrary command in the buffer.

The command's type must be included in the buffer specs. When the buffer is
applied, arbitrary commands are executed with `apply!(world, command)`.
"""
function record!(buf::CommandBuffer, command)
    push!(buf._commands, command)
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
        body = if T <: NewEntityCommand
            :(_apply_new_entity!(buf._world, cmd.entity, cmd.components))
        elseif T <: RemoveEntityCommand
            :(Ark.remove_entity!(buf._world, cmd.entity))
        elseif T <: AddComponentsCommand
            :(Ark.add_components!(buf._world, cmd.entity, cmd.components))
        elseif T <: RemoveComponentsCommand
            R = T.parameters[1]
            types = [fieldtype(R, i).parameters[1] for i in 1:fieldcount(R)]
            :(Ark.remove_components!(buf._world, cmd.entity, $(Expr(:tuple, types...))))
        elseif T <: ExchangeComponentsCommand
            R = T.parameters[2]
            types = [fieldtype(R, i).parameters[1] for i in 1:fieldcount(R)]
            :(Ark.exchange_components!(buf._world, cmd.entity; add=cmd.add,
                remove=($(Expr(:tuple, types...)))))
        elseif T <: SetComponentsCommand
            :(Ark.set_components!(buf._world, cmd.entity, cmd.components))
        elseif T <: SetRelationsCommand
            :(Ark.set_relations!(buf._world, cmd.entity, cmd.relations))
        else
            :(Ark.apply!(buf._world, cmd))
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

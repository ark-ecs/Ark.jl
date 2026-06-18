
"""
    StagedEntity

Identifier for an [Entity](@ref Entities) whose creation has been recorded in a
[CommandBuffer](@ref), but has not been applied to the [World](@ref) yet.

A `StagedEntity` is returned by [`new_entity!`](@ref) when entity creation is
staged through a command buffer. It reserves an entity identity for later use,
but the entity is not alive, is not stored in any archetype table, and cannot be
matched by queries until the command buffer is applied.

Use a staged entity to record additional commands that should affect the same
future entity, such as adding components, setting component values, or using it
as a relation target in the same command buffer.
"""
struct StagedEntity
    entity::Entity
end

Base.isless(a::StagedEntity, b::StagedEntity) = isless(a.entity, b.entity)

struct NewEntity{V<:Tuple}
    entity::Entity
    components::V
end

struct RemoveEntity
    entity::Entity
end

struct AddComponents{C<:Tuple}
    entity::Entity
    components::C
end

struct RemoveComponents{R<:Tuple}
    entity::Entity
end

struct ExchangeComponents{A<:Tuple,R<:Tuple}
    entity::Entity
    add::A
end

struct SetComponents{V<:Tuple}
    entity::Entity
    values::V
end

struct SetRelations{R<:Tuple}
    entity::Entity
    relations::R
end

struct CommandBuffer{C}
    commands::Vector{C}
end

function _cmd_value_type(T, relation_types::Type{<:Tuple})
    if T isa Type && _is_relation_type(T, relation_types)
        return Pair{T,Entity}
    end
    return T
end

@generated function _val_cmd_type(::Type{T}, ::typeof(new_entity!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    NewEntity{Tuple{inner...}}
end

@generated function _val_cmd_type(
    ::Type{T},
    ::typeof(new_entity!),
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    relation_types = _schema_relation_types(Storage)
    inner = [_cmd_value_type(fieldtype(T, i).parameters[1], relation_types) for i in 1:fieldcount(T)]
    NewEntity{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(add_components!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    AddComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(
    ::Type{T},
    ::typeof(add_components!),
    ::Type{Storage},
) where {T<:Tuple,Storage<:_WorldStorage}
    relation_types = _schema_relation_types(Storage)
    inner = [_cmd_value_type(fieldtype(T, i).parameters[1], relation_types) for i in 1:fieldcount(T)]
    AddComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(remove_components!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    RemoveComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(
    ::Type{T},
    ::typeof(exchange_components!),
    ::Type{U},
    ::Type{Storage},
) where {T<:Tuple,U<:Tuple,Storage<:_WorldStorage}
    relation_types = _schema_relation_types(Storage)
    add_inner = [_cmd_value_type(fieldtype(T, i).parameters[1], relation_types) for i in 1:fieldcount(T)]
    rem_inner = [fieldtype(U, i).parameters[1] for i in 1:fieldcount(U)]
    ExchangeComponents{Tuple{add_inner...},Tuple{rem_inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(set_components!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    SetComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(set_relations!)) where {T<:Tuple}
    pair_types = [Pair{DataType,Entity} for _ in 1:fieldcount(T)]
    SetRelations{Tuple{pair_types...}}
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

function _specs_to_types(world::World, specs::Tuple)
    n = length(specs)
    if n == 0
        throw(ArgumentError("command buffer needs to contain at least one deferred operation"))
    end
    storage_type = typeof(_storage(world))
    types = Vector{DataType}(undef, n)
    for i in 1:n
        spec = specs[i]
        fn = spec[1]
        types[i] = if fn === new_entity!
            _val_cmd_type(typeof(_valtuple(spec[2])), new_entity!, storage_type)
        elseif fn === remove_entity!
            RemoveEntity
        elseif fn === add_components!
            _val_cmd_type(typeof(_valtuple(spec[2])), add_components!, storage_type)
        elseif fn === remove_components!
            _val_cmd_type(typeof(_valtuple(spec[2])), remove_components!)
        elseif fn === exchange_components!
            add, remove = _exchange_spec_components(spec)
            _val_cmd_type(typeof(_valtuple(add)), exchange_components!, typeof(_valtuple(remove)), storage_type)
        elseif fn === set_components!
            _val_cmd_type(typeof(_valtuple(spec[2])), set_components!)
        elseif fn === set_relations!
            _val_cmd_type(typeof(_valtuple(spec[2])), set_relations!)
        else
            throw(ArgumentError("unknown command function $fn"))
        end
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
function CommandBuffer(world::World, specs::Tuple)
    cmd_types = _specs_to_types(world, specs)
    C = Union{cmd_types...}
    CommandBuffer{C}(Vector{C}())
end

function is_alive(::World, ::StagedEntity)
    return false
end

function new_entity!(world::World, buf::CommandBuffer, values::Tuple)
    state = _state(world)
    entity = _reserve_entity!(state)
    _reserve_entity_index!(state, entity)
    push!(buf.commands, NewEntity(entity, values))
    return StagedEntity(entity)
end

function remove_entity!(world::World, buf::CommandBuffer, entity::Entity)
    push!(buf.commands, RemoveEntity(entity))
    return nothing
end

function remove_entity!(world::World, buf::CommandBuffer, entity::StagedEntity)
    return remove_entity!(world, buf, entity.entity)
end

function add_components!(world::World, buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf.commands, AddComponents(entity, values))
    return nothing
end

function add_components!(world::World, buf::CommandBuffer, entity::StagedEntity, values::Tuple)
    return add_components!(world, buf, entity.entity, values)
end

@generated function _make_remove_cmd(entity::Entity, ::Type{T}) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    R = Tuple{inner...}
    quote
        RemoveComponents{$R}(entity)
    end
end

Base.@constprop :aggressive function remove_components!(world::World, buf::CommandBuffer, entity::Entity, types::Tuple)
    push!(buf.commands, _make_remove_cmd(entity, typeof(_valtuple(types))))
    return nothing
end

function remove_components!(world::World, buf::CommandBuffer, entity::StagedEntity, types::Tuple)
    return remove_components!(world, buf, entity.entity, types)
end

@generated function _make_exchange_cmd(
    entity::Entity,
    add::A,
    ::Type{T},
) where {A<:Tuple,T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    R = Tuple{inner...}
    return quote
        ExchangeComponents{$A,$R}(entity, add)
    end
end

Base.@constprop :aggressive function exchange_components!(
    world::World,
    buf::CommandBuffer,
    entity::Entity;
    add::Tuple=(),
    remove::Tuple=(),
)
    push!(buf.commands, _make_exchange_cmd(entity, add, typeof(_valtuple(remove))))
    return nothing
end

function exchange_components!(world::World, buf::CommandBuffer, entity::StagedEntity; add::Tuple=(), remove::Tuple=())
    return exchange_components!(world, buf, entity.entity; add=add, remove=remove)
end

function set_components!(world::World, buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf.commands, SetComponents(entity, values))
    return nothing
end

function set_components!(world::World, buf::CommandBuffer, entity::StagedEntity, values::Tuple)
    return set_components!(world, buf, entity.entity, values)
end

function set_relations!(world::World, buf::CommandBuffer, entity::Entity, relations::Tuple)
    push!(buf.commands, SetRelations(entity, relations))
    return nothing
end

function set_relations!(world::World, buf::CommandBuffer, entity::StagedEntity, relations::Tuple)
    return set_relations!(world, buf, entity.entity, relations)
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
    apply!(world::World, buf::CommandBuffer)

Executes all commands recorded in the buffer in FIFO order.

After execution the command buffer is cleared and can be reused.
"""
@generated function apply!(world::World, buf::CommandBuffer{C}) where C
    member_types = C isa Union ? Base.uniontypes(C) : (C,)

    err = :(throw(ErrorException("unreachable reached")))
    chain = err
    for T in member_types
        if T <: NewEntity
            body = :(_apply_new_entity!(world, cmd.entity, cmd.components))
        elseif T <: RemoveEntity
            body = :(Ark.remove_entity!(world, cmd.entity))
        elseif T <: AddComponents
            body = :(Ark.add_components!(world, cmd.entity, cmd.components))
        elseif T <: RemoveComponents
            R = T.parameters[1]
            types = [fieldtype(R, i) for i in 1:fieldcount(R)]
            body = :(Ark.remove_components!(world, cmd.entity, $(Expr(:tuple, types...))))
        elseif T <: ExchangeComponents
            R = T.parameters[2]
            types = [fieldtype(R, i) for i in 1:fieldcount(R)]
            body = :(Ark.exchange_components!(world, cmd.entity; add=cmd.add,
                remove=($(Expr(:tuple, types...)))))
        elseif T <: SetComponents
            body = :(Ark.set_components!(world, cmd.entity, cmd.values))
        elseif T <: SetRelations
            body = :(Ark.set_relations!(world, cmd.entity, cmd.relations))
        else
            throw(ErrorException("unreachable reached"))
        end
        if length(member_types) == 1
            chain = body
        else
            cond = :(cmd isa $T)
            chain = Expr(:if, cond, body, chain)
        end
    end

    return quote
        for cmd in buf.commands
            $chain
        end
        empty!(buf.commands)
        return nothing
    end
end

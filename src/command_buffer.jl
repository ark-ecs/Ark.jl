
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

"""
    CommandBuffer{C}

A buffer for staging structural changes to apply later.

Use [CommandBuffer](@ref CommandBuffer(::World, ::Tuple)) to create one,
record changes with [new_entity!](@ref), [remove_entity!](@ref),
[add_components!](@ref), [remove_components!](@ref),
[exchange_components!](@ref), [set_components!](@ref),
and [set_relations!](@ref), then apply them all at once with [apply!](@ref).

All recorded commands are stored in a `Vector{C}` and executed when `apply!` is called.

See the [manual](@ref "Command buffer") for details and examples.
"""
struct CommandBuffer{C}
    commands::Vector{C}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(new_entity!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    NewEntity{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(add_components!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    AddComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(remove_components!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    RemoveComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(exchange_components!), ::Type{U}) where {T<:Tuple, U<:Tuple}
    add_inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    rem_inner = [fieldtype(U, i).parameters[1] for i in 1:fieldcount(U)]
    ExchangeComponents{Tuple{add_inner...}, Tuple{rem_inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(set_components!)) where {T<:Tuple}
    inner = [fieldtype(T, i).parameters[1] for i in 1:fieldcount(T)]
    SetComponents{Tuple{inner...}}
end

@generated function _val_cmd_type(::Type{T}, ::typeof(set_relations!)) where {T<:Tuple}
    pair_types = [Pair{DataType, Entity} for _ in 1:fieldcount(T)]
    SetRelations{Tuple{pair_types...}}
end

function _specs_to_types(specs::Tuple)
    n = length(specs)
    if n == 0
        throw(ArgumentError("command buffer needs to contain at least one deferred operation"))
    end
    types = Vector{DataType}(undef, n)
    for i in 1:n
        spec = specs[i]
        fn = spec[1]
        types[i] = if fn === new_entity!
            _val_cmd_type(typeof(_valtuple(spec[2])), new_entity!)
        elseif fn === remove_entity!
            RemoveEntity
        elseif fn === add_components!
            _val_cmd_type(typeof(_valtuple(spec[2])), add_components!)
        elseif fn === remove_components!
            _val_cmd_type(typeof(_valtuple(spec[2])), remove_components!)
        elseif fn === exchange_components!
            _val_cmd_type(typeof(_valtuple(spec[2])), exchange_components!, typeof(_valtuple(spec[3])))
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

Creates a new command buffer for the given [World](@ref).

The `specs` tuple specifies which operations the buffer supports.
Each element is a tuple of the form `(function, component_types...)`:

```julia
buf = CommandBuffer(world, (
    (new_entity!, (Position, Velocity)),
    (remove_entity!,),
    (add_components!, (Velocity,)),
    (remove_components!, (Velocity,)),
    (exchange_components!, (Health,), (Velocity,)),
    (set_components!, (Position,)),
    (set_relations!, (ChildOf,)),
))
```

The component types are used to specialize the command types at construction time.
"""
function CommandBuffer(world::World, specs::Tuple)
    cmd_types = _specs_to_types(specs)
    C = Union{cmd_types...}
    CommandBuffer{C}(Vector{C}())
end

Ark.is_alive(::World, ::StagedEntity) = false

function new_entity!(world::World, buf::CommandBuffer, values::Tuple)
    state = _state(world)
    entity = _get_entity(state._entity_pool)
    id = Int(entity._id)
    if id > length(state._entities)
        push!(state._entities, _EntityIndex(UInt32(0), UInt32(0)))
        resize!(state._targets, id)
    end
    state._targets[id] = false
    push!(buf.commands, NewEntity(entity, values))
    return StagedEntity(entity)
end

function remove_entity!(world::World, buf::CommandBuffer, entity::Entity)
    push!(buf.commands, RemoveEntity(entity))
    return nothing
end

remove_entity!(world::World, buf::CommandBuffer, entity::StagedEntity) =
    remove_entity!(world, buf, entity.entity)

function add_components!(world::World, buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf.commands, AddComponents(entity, values))
    return nothing
end

add_components!(world::World, buf::CommandBuffer, entity::StagedEntity, values::Tuple) =
    add_components!(world, buf, entity.entity, values)

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

remove_components!(world::World, buf::CommandBuffer, entity::StagedEntity, types::Tuple) =
    remove_components!(world, buf, entity.entity, types)

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

Base.@constprop :aggressive function exchange_components!(world::World, buf::CommandBuffer, entity::Entity; add::Tuple=(), remove::Tuple=())
    push!(buf.commands, _make_exchange_cmd(entity, add, typeof(_valtuple(remove))))
    return nothing
end

exchange_components!(world::World, buf::CommandBuffer, entity::StagedEntity; add::Tuple=(), remove::Tuple=()) =
    exchange_components!(world, buf, entity.entity; add=add, remove=remove)

function set_components!(world::World, buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf.commands, SetComponents(entity, values))
    return nothing
end

set_components!(world::World, buf::CommandBuffer, entity::StagedEntity, values::Tuple) =
    set_components!(world, buf, entity.entity, values)

function set_relations!(world::World, buf::CommandBuffer, entity::Entity, relations::Tuple)
    push!(buf.commands, SetRelations(entity, relations))
    return nothing
end

set_relations!(world::World, buf::CommandBuffer, entity::StagedEntity, relations::Tuple) =
    set_relations!(world, buf, entity.entity, relations)

@generated function _new_entity_prealloc!(
    world_state::_WorldState,
    stores::Storage,
    entity::Entity,
    ::Val{TS},
    values::Tuple,
    ::TR,
    targets::Tuple{Vararg{Entity}},
) where {Storage<:_WorldStorage,TS<:Tuple,TR<:Tuple}
    types = _to_types(fieldtypes(TS))
    rel_types = _to_types(TR)
    relation_types = _schema_relation_types(Storage)

    _check_no_duplicates(types)
    _check_no_duplicates(rel_types)
    _check_relations(rel_types, relation_types)
    _check_is_subset(rel_types, types)

    CS = _schema_storage_types(Storage)
    ids = tuple(Int[_component_index(CS, T) for T in types]...)
    rel_ids = tuple(Int[_component_index(CS, T) for T in rel_types]...)
    num_ids = length(ids)
    use_map = num_ids >= 4 ? _UseMap() : _NoUseMap()

    M = max(1, cld(fieldcount(CS), 64))
    add_mask = _Mask{M}(ids...)
    rem_mask = _Mask{M}()

    world_has_rel = Val{_has_relations(relation_types)}()

    exprs = Expr[]
    push!(exprs, :(_check_relation_targets(world_state, targets)))
    push!(exprs, :(_check_locked(world_state)))
    push!(
        exprs,
        :(
            table = _find_or_create_table!(
                world_state,
                stores,
                world_state._tables[1],
                $ids,
                (),
                $rel_ids,
                targets,
                $add_mask,
                $rem_mask,
                $use_map,
                $world_has_rel,
            )[1]
        ),
    )
    push!(exprs, :(_place_entity!(world_state, entity, table)))

    for i in 1:length(types)
        T = types[i]
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        val_expr = :(values.$i)

        push!(exprs, :($stor_sym = _get_storage(stores, $T)))
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[table]))
        push!(exprs, :(push!($col_sym, $val_expr)))
    end

    push!(exprs, Expr(:return, :nothing))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

function _apply_new_entity!(world::World, entity::Entity, values::Tuple)
    values, relations = _normalize_relations(values, Val(:value))
    rel_types, targets = _relation_types_and_targets(relations)
    world_state = _state(world)
    world_storage = _storage(world)
    _new_entity_prealloc!(world_state, world_storage, entity,
        Val{typeof(values)}(), values, rel_types, targets)
    index = world_state._entities[entity._id]
    table = world_state._tables[index.table]
    mask = world_state._archetypes_hot[table.archetype].mask
    if _has_observers(world_state._event_manager, OnCreateEntity)
        _fire_create_entity(world_state._event_manager, entity, mask)
    end
    if !isempty(relations) && _has_observers(world_state._event_manager, OnAddRelations)
        _fire_create_entity_relations(world_state._event_manager, entity, mask)
    end
    return nothing
end

"""
    apply!(world::World, buf::CommandBuffer)

Executes all commands recorded in the buffer in FIFO order.

New entities are created via [new_entity!](@ref) with pre-allocated entity IDs,
and events `OnCreateEntity` / `OnAddRelations` are fired. All other commands
delegate to the corresponding [World](@ref) methods.

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
                remove=$(Expr(:tuple, types...))))
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


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
    types::R
end

struct ExchangeComponents{A<:Tuple,R<:Tuple}
    entity::Entity
    add::A
    remove::R
end

struct CommandBuffer{C}
    commands::Vector{C}
end

const _CMD_TYPES = Union{NewEntity{<:Tuple}, RemoveEntity, AddComponents{<:Tuple}, RemoveComponents{<:Tuple}, ExchangeComponents{<:Tuple,<:Tuple}}

@generated function CommandBuffer(::World, specs::T) where {T<:Tuple}
    cmd_types = Expr(:tuple)
    for i in 1:fieldcount(T)
        spec = fieldtype(T, i)
        spec isa DataType || error("spec must be a tuple, got $spec")
        if !(spec <: Tuple{Vararg{Any}}) || fieldcount(spec) < 1
            return :(throw(ArgumentError("each spec must be a tuple like (fn, types...)")))
        end
        fn_type = fieldtype(spec, 1)
        cmd_type = if fn_type <: typeof(new_entity!)
            if fieldcount(spec) < 2 || !(fieldtype(spec, 2) <: Tuple)
                return :(throw(ArgumentError("(new_entity!, types) spec needs a tuple of component types")))
            end
            NewEntity
        elseif fn_type <: typeof(remove_entity!)
            RemoveEntity
        elseif fn_type <: typeof(add_components!)
            if fieldcount(spec) < 2 || !(fieldtype(spec, 2) <: Tuple)
                return :(throw(ArgumentError("(add_components!, types) spec needs a tuple of component types")))
            end
            AddComponents
        elseif fn_type <: typeof(remove_components!)
            if fieldcount(spec) < 2 || !(fieldtype(spec, 2) <: Tuple)
                return :(throw(ArgumentError("(remove_components!, types) spec needs a tuple of component types")))
            end
            RemoveComponents
        elseif fn_type <: typeof(exchange_components!)
            if fieldcount(spec) < 3 || !(fieldtype(spec, 2) <: Tuple) || !(fieldtype(spec, 3) <: Tuple)
                return :(throw(ArgumentError("(exchange_components!, add_types, remove_types) spec needs two tuples")))
            end
            ExchangeComponents
        else
            return :(throw(ArgumentError(
                "unknown command function in spec, expected new_entity!, remove_entity!, " *
                "add_components!, remove_components!, or exchange_components!")))
        end
        push!(cmd_types.args, cmd_type)
    end
    C = Expr(:curly, :Union, cmd_types.args...)
    quote
        CommandBuffer{$C}(Vector{$C}())
    end
end

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
    return entity
end

function remove_entity!(world::World, buf::CommandBuffer, entity::Entity)
    push!(buf.commands, RemoveEntity(entity))
    return nothing
end

function add_components!(world::World, buf::CommandBuffer, entity::Entity, values::Tuple)
    push!(buf.commands, AddComponents(entity, values))
    return nothing
end

function remove_components!(world::World, buf::CommandBuffer, entity::Entity, types::Tuple)
    push!(buf.commands, RemoveComponents(entity, types))
    return nothing
end

function exchange_components!(world::World, buf::CommandBuffer, entity::Entity; add::Tuple=(), remove::Tuple=())
    push!(buf.commands, ExchangeComponents(entity, add, remove))
    return nothing
end

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

@generated function apply!(world::World, buf::CommandBuffer{C}) where C
    member_types = C isa Union ? Base.uniontypes(C) : (C,)

    err = :(error("unrecognized command type: ", typeof(cmd)))
    chain = err
    for T in reverse(member_types)
        cond = :(cmd isa $T)
        if T <: NewEntity
            body = :(_apply_new_entity!(world, cmd.entity, cmd.components))
        elseif T <: RemoveEntity
            body = :(Ark.remove_entity!(world, cmd.entity))
        elseif T <: AddComponents
            body = :(Ark.add_components!(world, cmd.entity, cmd.components))
        elseif T <: RemoveComponents
            body = :(Ark.remove_components!(world, cmd.entity, cmd.types))
        elseif T <: ExchangeComponents
            body = :(Ark.exchange_components!(world, cmd.entity; add=cmd.add, remove=cmd.remove))
        else
            continue
        end
        chain = Expr(:if, cond, body, chain)
    end

    return quote
        for cmd in buf.commands
            $chain
        end
        empty!(buf.commands)
        return nothing
    end
end

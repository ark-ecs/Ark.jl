
"""
    new_entities!(
        [f::Function],
        world::World,
        n::Int,
        components::Tuple;
        relations:Tuple=(),
    )

Creates the given number of [entities](@ref Entity).
Components can be given as types or as default values.
In the latter case, types are inferred from the add values.

A callback/`do`-block can be run on the newly created entities e.g. for individual initialization.
It takes a tuple of `(entities, columns...)` as argument, with a column for each added component.
The callback is mandatory if components are given as types.
Note that components are not initialized/undef unless set in the callback in this case.

# Arguments

  - `f::Function`: Optional callback for initialization, can be passed as a `do` block.
  - `world::World`: The [World](@ref) instance to use.
  - `n::Int`: The number of entities to create.
  - `components::Tuple`: A tuple of component to add. Either default values like `(Position(0, 0), Velocity(1, 1))`, or types like `(Position, Velocity)`.
  - `relations::Tuple`: Relationship component type => target entity pairs.
  - `iterate::Bool`: Whether to return a batch for individual entity initialization.

# Examples

Create 100 entities from default values:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
new_entities!(world, 100, (Position(0, 0), Velocity(1, 1)))

# output

```

Create 100 entities from component types and initialize them:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
new_entities!(world, 100, (Position, Velocity)) do (entities, positions, velocities)
    for i in eachindex(entities)
        positions[i] = Position(rand(), rand())
        velocities[i] = Velocity(1, 1)
    end
end

# output

```
"""
Base.@constprop :aggressive function new_entities!(
    fn::F,
    world::World,
    n::Int,
    components::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
) where {F}
    if n == 0
        return
    end
    if components isa Tuple{Vararg{DataType}}
        rel_types = ntuple(i -> Val(relations[i].first), length(relations))
        targets = ntuple(i -> relations[i].second, length(relations))
        return _new_entities!(fn, world, UInt32(n),
            ntuple(i -> Val(components[i]), length(components)), (),
            rel_types, targets, Val(false), Val(true))
    else
        rel_types = ntuple(i -> Val(relations[i].first), length(relations))
        targets = ntuple(i -> relations[i].second, length(relations))
        return _new_entities!(fn, world, UInt32(n),
            Val{typeof(components)}(), components,
            rel_types, targets, Val(true), Val(true))
    end
end

Base.@constprop :aggressive function new_entities!(
    world::World,
    n::Int,
    components::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
)
    if n == 0
        return
    end
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return _new_entities!(world, UInt32(n),
        Val{typeof(components)}(), components,
        rel_types, targets, Val(true), Val(false)) do tuple
    end
end

function _get_tables(
    world::World,
    arches::Vector{_Archetype{M}},
    arches_hot::Vector{_ArchetypeHot{M}},
    filter::F,
)::Tuple{Vector{UInt32},Bool} where {M,F<:Filter}
    if _is_cached(filter._filter)
        tables = filter._filter.tables.ids
        any_relations = false
        for table_id in tables
            if _has_relations(world._tables[table_id])
                any_relations = true
            end
        end
        return tables, any_relations
    end

    tables = world._pool.tables
    any_relations = false
    for arch in eachindex(arches)
        @inbounds archetype_hot = arches_hot[arch]
        if !_matches(filter._filter, archetype_hot)
            continue
        end
        if !archetype_hot.has_relations
            table = @inbounds world._tables[Int(archetype_hot.table)]
            if isempty(table.entities)
                continue
            end
            push!(tables, table.id)
            continue
        end
        archetype = @inbounds arches[arch]
        if isempty(archetype.tables)
            continue
        end
        arch_tables = _get_tables(world, archetype, filter._filter.relations)
        for table_id in arch_tables
            table = @inbounds world._tables[Int(table_id)]
            if !isempty(table.entities) && _matches(world._relations, table, filter._filter.relations)
                push!(tables, table.id)
                any_relations = true
            end
        end
    end

    return tables, any_relations
end

@generated function _get_archetypes(world::W, filter::F) where {W<:World,F<:Filter}
    CS = W.parameters[1]
    TS = F.parameters[2]
    OPT = F.parameters[4]

    comp_types = _to_types(TS.parameters)
    optional_flags = OPT.parameters

    required_ids = [_component_id(CS, comp_types[i]) for i in 1:length(comp_types) if optional_flags[i] === Val{false}]
    ids_tuple = tuple(required_ids...)

    # TODO: skip this for cached filters
    archetypes =
        length(ids_tuple) == 0 ? :((world._archetypes, world._archetypes_hot)) :
        :(_get_archetypes(world, $ids_tuple))

    quote
        return $archetypes
    end
end

"""
    remove_entities!([f::Function], world::World, filter::Filter)

Removes all entities that match the given [Filter](@ref) from the [World](@ref).

The optional callback/`do` block is called on them before the removal.
The callback's argument is an [Entities](@ref) list.

# Example

Removing entities:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Position, Velocity))
remove_entities!(world, filter)

# output

```

Removing entities using a callback:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Position, Velocity))
remove_entities!(world, filter) do entities
    # do something with the entities.
end

# output

```
"""
function remove_entities!(world::W, filter::F) where {W<:World,F<:Filter}
    _remove_entities!(world, filter, Val(false)) do entities
    end
end

function remove_entities!(fn::Fn, world::W, filter::F) where {Fn,W<:World,F<:Filter}
    _remove_entities!(fn, world, filter, Val(true))
end

"""
    set_relations!([f::Function], world::World, filter::Filter::Entity, relations::Tuple)

Sets relation targets for the given components of all [entities](@ref Entity) matching the given [Filter](@ref).
Optionally runs a callback/`do`-block on the affected entities.

# Example

Setting relation targets:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (ChildOf,); relations=(ChildOf => parent,))
set_relations!(world, filter, (ChildOf => parent2,))

# output

```

Setting relation targets and running a callback:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (ChildOf,); relations=(ChildOf => parent,))
set_relations!(world, filter, (ChildOf => parent2,)) do entities
    # do something with the entities...
end

# output

```
"""
@inline Base.@constprop :aggressive function set_relations!(
    fn::Fn,
    world::W,
    filter::F,
    relations::Tuple,
) where {Fn,W<:World,F<:Filter}
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _set_relations_batch!(fn, world, filter, rel_types, targets, Val(true))
end

@inline Base.@constprop :aggressive function set_relations!(
    world::W,
    filter::F,
    relations::Tuple,
) where {W<:World,F<:Filter}
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _set_relations_batch!(world, filter, rel_types, targets, Val(false)) do _
    end
end

"""
    add_components!(
        [f::Function]
        world::World,
        filter::Filter,
        add::Tuple=(),
        relations::Tuple=(),
    )

Adds components to all [entities](@ref Entity) matching the given [Filter](@ref).

Components can be added as types or as values.
In the latter case, types are inferred from the add values.

A callback/`do`-block can be run on the affected entities e.g. for individual initialization.
It takes a tuple of `(entities, columns...)` as argument, with a column for each added component.
The callback is mandatory if components are added as types.
Note that components are not initialized/undef unless set in the callback in this case.

# Arguments

  - `f::Function`: Optional callback for initialization, can be passed as a `do` block.
  - `world::World`: The [World](@ref) instance to use.
  - `filter::Filter`: The [Filter](@ref) to select entities.
  - `add::Tuple`: A tuple of component to add. Either default values like `(Position(0, 0), Velocity(1, 1))`, or types like `(Position, Velocity)`.
  - `relations::Tuple`: Relationship component type => target entity pairs.

# Examples

Adding values, not using the callback:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Velocity,))
add_components!(world, filter, (Health(100),))

# output

```

Adding as types, using the callback for initialization:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Velocity,))
add_components!(world, filter, (Health,)) do (entities, healths)
    for i in eachindex(entities, healths)
        healths[i] = Health(i * 2)
    end
end

# output

```
"""
@inline Base.@constprop :aggressive function add_components!(
    fn::Fn,
    world::World,
    filter::F,
    add::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
) where {Fn,F<:Filter}
    if add isa Tuple{Vararg{DataType}}
        rel_types = ntuple(i -> Val(relations[i].first), length(relations))
        targets = ntuple(i -> relations[i].second, length(relations))
        return @inline _exchange_components!(
            fn, world, filter,
            ntuple(i -> Val(add[i]), length(add)), (),
            (),
            rel_types, targets,
            Val(false), Val(true), Val(false),
        )
    else
        rel_types = ntuple(i -> Val(relations[i].first), length(relations))
        targets = ntuple(i -> relations[i].second, length(relations))
        return @inline _exchange_components!(
            fn, world, filter,
            Val{typeof(add)}(), add,
            (),
            rel_types, targets,
            Val(true), Val(true), Val(false),
        )
    end
end

@inline Base.@constprop :aggressive function add_components!(
    world::World,
    filter::F,
    add::Tuple;
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
) where {F<:Filter}
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _exchange_components!(
        world, filter,
        Val{typeof(add)}(), add,
        (),
        rel_types, targets,
        Val(true), Val(false), Val(false),
    ) do _
    end
end

"""
    remove_components!(
        [f::Function]
        world::World,
        filter::Filter,
        remove::Tuple=(),
    )

Removes components from all [entities](@ref Entity) matching the given [Filter](@ref).

A callback/`do`-block can be run on the affected entities.
It takes an [entities column](@ref Ark.Entities) as argument.

# Arguments

  - `f::Function`: Optional callback for initialization, can be passed as a `do` block.
  - `world::World`: The [World](@ref) instance to use.
  - `filter::Filter`: The [Filter](@ref) to select entities.
  - `remove::Tuple`: A tuple of component types to remove, like `(Position, Velocity)`

# Examples

Removing components, not using the callback:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Velocity,))
remove_components!(world, filter, (Velocity,))

# output

```

Removing components, using the optional callback:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Velocity,))
remove_components!(world, filter, (Velocity,)) do entities
    # do something with the entities...
end

# output

```
"""
@inline Base.@constprop :aggressive function remove_components!(
    fn::Fn,
    world::World,
    filter::F,
    remove::Tuple,
) where {Fn,F<:Filter}
    return @inline _exchange_components!(
        fn, world, filter,
        Val{Tuple{}}(), (),
        ntuple(i -> Val(remove[i]), length(remove)),
        (), (),
        Val(false), Val(true), Val(true),
    )
end

@inline Base.@constprop :aggressive function remove_components!(
    world::World,
    filter::F,
    remove::Tuple,
) where {F<:Filter}
    return @inline _exchange_components!(
        world, filter,
        Val{Tuple{}}(), (),
        ntuple(i -> Val(remove[i]), length(remove)),
        (), (),
        Val(false), Val(false), Val(true),
    ) do _
    end
end

"""
    exchange_components!(
        [f::Function]
        world::World,
        filter::Filter;
        add::Tuple=(),
        remove::Tuple=(),
        relations::Tuple=(),
    )

Adds and removes components on all [entities](@ref Entity) matching the given [Filter](@ref).

Components can be added as types or as values.
In the latter case, types are inferred from the add values.

A callback/`do`-block can be run on the affected entities e.g. for individual initialization.
It takes a tuple of `(entities, columns...)` as argument, with a column for each added component.
The callback is mandatory if components are added as types.
Note that components are not initialized/undef unless set in the callback in this case.

# Arguments

  - `f::Function`: Optional callback for initialization, can be passed as a `do` block.
  - `world::World`: The [World](@ref) instance to use.
  - `filter::Filter`: The [Filter](@ref) to select entities.
  - `add::Tuple`: A tuple of component to add. Either default values like `(Position(0, 0), Velocity(1, 1))`, or types like `(Position, Velocity)`.
  - `remove::Tuple`: A tuple of component types to remove, like `(Position, Velocity)`
  - `relations::Tuple`: Relationship component type => target entity pairs.

# Examples

Adding values, not using the callback:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Velocity,))
exchange_components!(world, filter;
    add=(Health(100),),
    remove=(Velocity,),
)

# output

```

Adding as types, using the callback for initialization:

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
filter = Filter(world, (Velocity,))
exchange_components!(world, filter;
    add=(Health,),
    remove=(Velocity,),
) do (entities, healths)
    for i in eachindex(entities, healths)
        healths[i] = Health(i * 2)
    end
end

# output

```
"""
@inline Base.@constprop :aggressive function exchange_components!(
    fn::Fn,
    world::World,
    filter::F;
    add::Tuple=(),
    remove::Tuple=(),
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
) where {Fn,F<:Filter}
    if add isa Tuple{Vararg{DataType}}
        rel_types = ntuple(i -> Val(relations[i].first), length(relations))
        targets = ntuple(i -> relations[i].second, length(relations))
        return @inline _exchange_components!(
            fn, world, filter,
            ntuple(i -> Val(add[i]), length(add)), (),
            ntuple(i -> Val(remove[i]), length(remove)),
            rel_types, targets,
            Val(false), Val(true), Val(false),
        )
    else
        rel_types = ntuple(i -> Val(relations[i].first), length(relations))
        targets = ntuple(i -> relations[i].second, length(relations))
        return @inline _exchange_components!(
            fn, world, filter,
            Val{typeof(add)}(), add,
            ntuple(i -> Val(remove[i]), length(remove)),
            rel_types, targets,
            Val(true), Val(true), Val(false),
        )
    end
end

@inline Base.@constprop :aggressive function exchange_components!(
    world::World,
    filter::F;
    add::Tuple=(),
    remove::Tuple=(),
    relations::Tuple{Vararg{Pair{DataType,Entity}}}=(),
) where {F<:Filter}
    rel_types = ntuple(i -> Val(relations[i].first), length(relations))
    targets = ntuple(i -> relations[i].second, length(relations))
    return @inline _exchange_components!(
        world, filter,
        Val{typeof(add)}(), add,
        ntuple(i -> Val(remove[i]), length(remove)),
        rel_types, targets,
        Val(true), Val(false), Val(false),
    ) do _
    end
end

@generated function _set_relations_batch!(
    fn::Fn,
    world::W,
    filter::F,
    ::TR,
    targets::Tuple{Vararg{Entity}},
    ::HFN,
) where {Fn,W<:World,F<:Filter,TR<:Tuple,HFN<:Val}
    rel_types = _to_types(TR)

    _check_no_duplicates(rel_types)
    _check_relations(rel_types)

    rel_ids = tuple([_component_id(W.parameters[1], T) for T in rel_types]...)

    has_fn = HFN == Val{true}
    return quote
        _check_locked(world)

        _lock(world._lock)

        arches, arches_hot = _get_archetypes(world, filter)
        tables, _ = _get_tables(world, arches, arches_hot, filter)
        batches = world._pool.batches

        for table_id in tables
            old_table = world._tables[table_id]
            if isempty(old_table)
                continue
            end
            # TODO: use a simplified data structure?
            push!(
                batches,
                _BatchTable(old_table, world._archetypes[old_table.archetype], UInt32(1), UInt32(length(old_table))),
            )
        end
        if !_is_cached(filter._filter) # Do not clear for cached filters!!!
            empty!(tables)
        end

        for batch in batches
            _set_relations_table!(fn, world, batch, $rel_ids, targets, $has_fn)
        end

        empty!(batches)

        _unlock(world._lock)

        return nothing
    end
end

function _set_relations_table!(
    fn::Fn,
    world::W,
    batch::_BatchTable,
    relations::Tuple{Vararg{Int}},
    targets::Tuple{Vararg{Entity}},
    has_fn::Bool,
) where {Fn,W<:World}
    new_relations, changed, mask = _get_exchange_targets(world, batch.table, relations, targets)
    if !changed
        empty!(new_relations)
        return nothing
    end

    new_table, found = _get_table(world, batch.archetype, new_relations)
    if !found
        new_table_id = _create_table!(world, batch.archetype, copy(new_relations))
        new_table = world._tables[new_table_id]
    end
    empty!(new_relations)

    if _has_observers(world._event_manager, OnRemoveRelations)
        _fire_set_relations(world._event_manager, OnRemoveRelations, batch, mask)
    end

    start_idx = length(new_table) + 1
    _move_entities!(world, batch.table.id, new_table.id, batch.end_idx)
    if has_fn
        fn(view(new_table.entities, start_idx:length(new_table)))
    end

    if _has_observers(world._event_manager, OnAddRelations)
        _fire_set_relations(
            world._event_manager,
            OnAddRelations,
            _BatchTable(
                new_table, world._archetypes[new_table.archetype],
                UInt32(start_idx), UInt32(length(new_table)),
            ),
            mask,
        )
    end
end

@generated function _exchange_components!(
    fn::Fn,
    world::W,
    filter::F,
    ::ATS,
    add::Tuple,
    ::RTS,
    ::TR,
    targets::Tuple{Vararg{Entity}},
    ::DEF,
    ::HFN,
    ::REM,
) where {Fn,W<:World,F<:Filter,ATS,RTS<:Tuple,TR<:Tuple,DEF<:Val,HFN<:Val,REM<:Val}
    add_types = _to_types(ATS)
    rem_types = _to_types(RTS)
    rel_types = _to_types(TR)

    if isempty(add_types) && isempty(rem_types)
        throw(ArgumentError("either components to add or to remove must be given for exchange_components!"))
    end

    _check_no_duplicates(add_types)
    _check_no_duplicates(rem_types)
    _check_if_intersect(add_types, rem_types)
    _check_no_duplicates(rel_types)
    _check_relations(rel_types)
    _check_is_subset(rel_types, add_types)

    return quote
        _check_locked(world)
        _lock(world._lock)

        arches, arches_hot = _get_archetypes(world, filter)
        tables, _ = _get_tables(world, arches, arches_hot, filter)
        batches = world._pool.batches

        for table_id in tables
            old_table = world._tables[table_id]
            if isempty(old_table)
                continue
            end
            # TODO: use a simplified data structure?
            push!(
                batches,
                _BatchTable(old_table, world._archetypes[old_table.archetype], UInt32(1), UInt32(length(old_table))),
            )
        end
        if !_is_cached(filter._filter) # Do not clear for cached filters!!!
            empty!(tables)
        end

        for batch in batches
            _exchange_components_table!(fn, world, batch,
                Val{$ATS}(), add, Val{$RTS}(), Val{$TR}(), targets, Val{$DEF}(), Val{$HFN}(), Val{$REM}())
        end

        empty!(batches)

        _unlock(world._lock)

        return nothing
    end
end

@generated function _exchange_components_table!(
    fn::Fn,
    world::W,
    batch::_BatchTable,
    ::ATS,
    add::Tuple,
    ::Val{RTS},
    ::Val{TR},
    targets::Tuple{Vararg{Entity}},
    ::Val{DEF},
    ::Val{HFN},
    ::Val{REM},
) where {Fn,W<:World,ATS,RTS<:Tuple,TR<:Tuple,DEF<:Val,HFN<:Val,REM<:Val}
    add_types = _to_types(ATS)
    rem_types = _to_types(RTS)
    rel_types = _to_types(TR)

    exprs = []

    CS = W.parameters[1]
    add_ids = tuple([_component_id(CS, T) for T in add_types]...)
    rem_ids = tuple([_component_id(CS, T) for T in rem_types]...)
    rel_ids = tuple([_component_id(CS, T) for T in rel_types]...)

    num_ids = length(add_ids) + length(rem_ids)
    use_map = num_ids >= 4 ? _UseMap() : _NoUseMap()

    M = max(1, cld(length(CS.parameters), 64))
    add_mask = _Mask{M}(add_ids...)
    rem_mask = _Mask{M}(rem_ids...)

    world_has_rel = Val{_has_relations(CS)}()
    adds_relations = !isempty(rel_types)

    push!(
        exprs,
        :(
            new_table_tuple =
                _find_or_create_table!(
                    world, batch.table, $add_ids, $rem_ids, $rel_ids, targets, $add_mask, $rem_mask, $use_map,
                    $world_has_rel,
                )
        ),
    )
    push!(exprs, :(new_table_index = new_table_tuple[1]))
    push!(exprs, :(relations_removed = new_table_tuple[2]))
    push!(exprs, :(new_table = world._tables[new_table_index]))

    if length(rem_types) > 0
        push!(
            exprs,
            :(
                begin
                    has_comp_obs = _has_observers(world._event_manager, OnRemoveComponents)
                    has_rel_obs = relations_removed && _has_observers(world._event_manager, OnRemoveRelations)
                    if has_comp_obs || has_rel_obs
                        old_mask = world._archetypes_hot[batch.table.archetype].mask
                        new_mask = world._archetypes_hot[new_table.archetype].mask
                        if has_comp_obs
                            _fire_remove(
                                world._event_manager,
                                OnRemoveComponents, batch,
                                old_mask, new_mask,
                            )
                        end
                        if has_rel_obs
                            _fire_remove(
                                world._event_manager,
                                OnRemoveRelations, batch,
                                old_mask, new_mask,
                            )
                        end
                    end
                end
            ),
        )
    end

    push!(exprs, :(start_idx = length(new_table) + 1))
    push!(exprs, :(_move_entities!(world, batch.table.id, new_table.id, batch.end_idx)))

    if DEF === Val{true}
        for i in 1:length(add_types)
            T = add_types[i]
            stor_sym = Symbol("stor", i)
            col_sym = Symbol("col", i)
            val_expr = :(add.$i)

            push!(exprs, :($stor_sym = _get_storage(world, $T)))
            push!(exprs, :(@inbounds $col_sym = $stor_sym.data[new_table_index]))
            push!(exprs, :(@inbounds fill!(view($col_sym, start_idx:length($col_sym)), $val_expr)))
        end
    end

    types_tuple_type_expr = Expr(:curly, :Tuple, [:($T) for T in add_types]...)
    ts_val_expr = :(Val{$(types_tuple_type_expr)}())

    if HFN == Val{true}
        if REM == Val{true}
            push!(exprs, :(fn(view(new_table.entities, start_idx:length(new_table)))))
        else
            push!(
                exprs,
                :(
                    begin
                        columns =
                            _get_columns(world, $ts_val_expr, new_table, UInt32(start_idx), UInt32(length(new_table)))
                        fn(columns)
                    end
                ),
            )
        end
    end

    if !isempty(add_types)
        push!(
            exprs,
            :(
                begin
                    has_comp_obs = _has_observers(world._event_manager, OnAddComponents)
                    has_rel_obs = $adds_relations && _has_observers(world._event_manager, OnAddRelations)
                    if has_comp_obs || has_rel_obs
                        new_archetype = world._archetypes[new_table.archetype]
                        old_mask = world._archetypes_hot[batch.table.archetype].mask
                        batch_table = _BatchTable(
                            new_table, new_archetype,
                            UInt32(start_idx), UInt32(length(new_table)),
                        )
                        if has_comp_obs
                            _fire_add(
                                world._event_manager,
                                OnAddComponents, batch_table,
                                old_mask, new_archetype.node.mask,
                            )
                        end
                        if has_rel_obs
                            _fire_add(
                                world._event_manager,
                                OnAddRelations, batch_table,
                                old_mask, new_archetype.node.mask,
                            )
                        end
                    end
                end
            ),
        )
    end

    push!(exprs, Expr(:return, :nothing))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _remove_entities!(fn::Fn, world::W, filter::F, ::HFN) where {Fn,W<:World,F<:Filter,HFN<:Val}
    CS = W.parameters[1]
    world_has_rel = _has_relations(CS)
    has_fn = HFN == Val{true}
    quote
        _check_locked(world)

        arches, arches_hot = _get_archetypes(world, filter)
        tables, any_relations = _get_tables(world, arches, arches_hot, filter)

        has_entity_obs = _has_observers(world._event_manager, OnRemoveEntity)
        has_rel_obs = any_relations && _has_observers(world._event_manager, OnRemoveRelations)
        has_callback = $has_fn
        should_lock = has_entity_obs || has_rel_obs || has_callback

        if should_lock
            _lock(world._lock)
        end

        $(has_fn ?
          :(
            for table_id in tables
                table = world._tables[table_id]
                if isempty(table)
                    continue
                end
                fn(table.entities)
            end
        ) :
          (:(nothing))
        )

        if has_entity_obs
            for table_id in tables
                table = world._tables[table_id]
                if isempty(table)
                    continue
                end
                _fire_remove_entities(
                    world._event_manager,
                    table,
                    world._archetypes_hot[table.archetype].mask,
                )
            end
        end
        if has_rel_obs
            for table_id in tables
                table = world._tables[table_id]
                if isempty(table)
                    continue
                end
                if _has_relations(table)
                    _fire_remove_entities_relations(
                        world._event_manager,
                        table,
                        world._archetypes_hot[table.archetype].mask,
                    )
                end
            end
        end

        cleanup = world._pool.entities
        for table_id in tables
            table = world._tables[table_id]
            if isempty(table)
                continue
            end
            for entity in table.entities
                $(world_has_rel ?
                  :(
                    if world._targets[entity._id]
                        push!(cleanup, entity)
                    end
                ) :
                  (:(nothing))
                )
                _recycle(world._entity_pool, entity)
            end
            empty!(table)
            for comp in world._archetypes[table.archetype].components
                _clear_component_data!(world, comp, table.id)
            end
        end

        $(world_has_rel ?
          :(
            for entity in cleanup
                _cleanup_archetypes(world, entity)
                world._targets[entity._id] = false
            end
        ) :
          (:(nothing))
        )

        if should_lock
            _unlock(world._lock)
        end

        if !_is_cached(filter._filter) # Do not clear for cached filters!!!
            empty!(tables)
        end
        empty!(cleanup)

        return nothing
    end
end

@generated function _new_entities!(
    fn::F,
    world::W,
    n::UInt32,
    ::TS,
    values::Tuple,
    ::TR,
    targets::Tuple{Vararg{Entity}},
    ::DEF,
    ::HFN,
) where {F,W<:World,TS,TR<:Tuple,DEF<:Val,HFN<:Val}
    types = _to_types(TS)
    rel_types = _to_types(TR)

    _check_no_duplicates(types)
    _check_no_duplicates(rel_types)
    _check_relations(rel_types)
    _check_is_subset(rel_types, types)

    CS = W.parameters[1]
    ids = tuple([_component_id(CS, T) for T in types]...)
    rel_ids = tuple([_component_id(CS, T) for T in rel_types]...)
    num_ids = length(ids)
    use_map = num_ids >= 4 ? _UseMap() : _NoUseMap()

    M = max(1, cld(length(CS.parameters), 64))
    add_mask = _Mask{M}(ids...)
    rem_mask = _Mask{M}()

    world_has_rel = Val{_has_relations(CS)}()

    exprs = []
    push!(exprs, :(_check_locked(world)))
    push!(
        exprs,
        :(
            table_idx = _find_or_create_table!(
                world,
                world._tables[1],
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
    push!(exprs, :(indices = _create_entities!(world, table_idx, n)))
    push!(exprs, :(table = world._tables[table_idx]))

    if length(types) > 0 && DEF === Val{true}
        body_exprs = Expr(:block)
        for i in 1:length(types)
            T = types[i]
            stor_sym = Symbol("stor", i)
            col_sym = Symbol("col", i)
            val_expr = :(values.$i)

            push!(body_exprs.args, :($stor_sym = _get_storage(world, $T)))
            push!(body_exprs.args, :(@inbounds $col_sym = $stor_sym.data[table_idx]))
            push!(body_exprs.args, :(fill!(view($col_sym, Int(indices[1]):Int(indices[2])), $val_expr)))
        end
        push!(exprs, :(
            if !isempty(values)
                $(body_exprs)
            end
        ))
    end

    types_tuple_type_expr = Expr(:curly, :Tuple, [:($T) for T in types]...)
    ts_val_expr = :(Val{$(types_tuple_type_expr)}())

    if HFN == Val{true}
        push!(
            exprs,
            :(
                begin
                    _lock(world._lock)
                    columns = _get_columns(world, $ts_val_expr, table, indices...)
                    fn(columns)

                    batch = _BatchTable(table, world._archetypes[table.archetype], indices...)
                    if _has_observers(world._event_manager, OnCreateEntity)
                        _fire_create_entities(world._event_manager, batch)
                    end
                    if _has_relations(table) && _has_observers(world._event_manager, OnAddRelations)
                        _fire_create_entities_relations(world._event_manager, batch)
                    end
                    _unlock(world._lock)
                    return nothing
                end
            ),
        )
    else
        push!(
            exprs,
            :(
                begin
                    has_entity_obs = _has_observers(world._event_manager, OnCreateEntity)
                    has_rel_obs = _has_relations(table) && _has_observers(world._event_manager, OnAddRelations)
                    if has_entity_obs || has_rel_obs
                        _lock(world._lock)
                        batch = _BatchTable(table, world._archetypes[table.archetype], indices...)
                        if has_entity_obs
                            _fire_create_entities(world._event_manager, batch)
                        end
                        if has_rel_obs
                            _fire_create_entities_relations(world._event_manager, batch)
                        end
                        _unlock(world._lock)
                    end
                    return nothing
                end
            ),
        )
    end

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _get_columns(
    world::W,
    ::Val{TS},
    table::_Table,
    start_idx::UInt32,
    end_idx::UInt32,
) where {W<:World,TS<:Tuple}
    CS = W.parameters[1]
    comp_types = TS.parameters
    world_storage_modes = W.parameters[3].parameters

    storage_modes = [
        world_storage_modes[_component_id(CS, T)]
        for T in comp_types
    ]

    exprs = Expr[]
    push!(exprs, :(entities = view(table.entities, Int(start_idx):Int(end_idx))))
    for i in 1:length(comp_types)
        stor_sym = Symbol("stor", i)
        col_sym = Symbol("col", i)
        vec_sym = Symbol("vec", i)
        push!(exprs, :(@inbounds $stor_sym = _get_storage(world, $(comp_types[i]))))
        push!(exprs, :(@inbounds $col_sym = $stor_sym.data[Int(table.id)]))

        if storage_modes[i].parameters[1] <: GPUVector
            push!(exprs, :($vec_sym = view(($col_sym).mem, Int(start_idx):Int(end_idx))))
        elseif storage_modes[i] == Storage{StructArray} || storage_modes[i].parameters[1] <: GPUStructArray ||
               fieldcount(comp_types[i]) == 0
            push!(exprs, :($vec_sym = view($col_sym, Int(start_idx):Int(end_idx))))
        else
            push!(exprs, :($vec_sym = FieldViewable(view($col_sym, Int(start_idx):Int(end_idx)))))
        end
    end
    result_exprs = [:entities]
    for i in 1:length(comp_types)
        push!(result_exprs, Symbol("vec", i))
    end
    result_exprs = map(x -> :($x), result_exprs)
    push!(exprs, Expr(:return, Expr(:tuple, result_exprs...)))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

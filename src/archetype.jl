
struct _ArchetypeHot{M}
    mask::_Mask{M}
    table::UInt32
    has_relations::Bool
end

function _ArchetypeHot(node::_GraphNode, table::UInt32)
    _ArchetypeHot(
        node.mask,
        table,
        false,
    )
end

function _ArchetypeHot(
    node::_GraphNode,
    table::UInt32,
    relations::Vector{Int},
)
    _ArchetypeHot(
        node.mask,
        table,
        !isempty(relations),
    )
end

mutable struct _Archetype{M}
    const components::Memory{Int}
    const tables::_IdCollection
    const index::Vector{_Linear_Map{UInt32,_IdCollection,true,false,NoZero,_IdCollection}}
    const target_tables::_Linear_Map{UInt32,_IdCollection,true,false,NoZero,_IdCollection}
    const free_tables::Vector{UInt32}
    const node::_GraphNode{M}
    const num_relations::UInt32
    const table::UInt32
    const id::UInt32
end

function _Archetype(id::UInt32, node::_GraphNode, table::UInt32)
    _Archetype(
        Memory{Int}(),
        _IdCollection(table),
        Vector{_Linear_Map{UInt32,_IdCollection,true,false,NoZero,_IdCollection}}(),
        _Linear_Map{UInt32,_IdCollection}(; zero_value=_empty_id_collection),
        Vector{UInt32}(),
        node,
        UInt32(0),
        table,
        id,
    )
end

function _Archetype(
    id::UInt32,
    node::_GraphNode,
    table::UInt32,
    relations::Vector{Int},
    components::Vector{Int},
)
    _Archetype(
        Memory{Int}(components),
        _IdCollection(),
        [_Linear_Map{UInt32,_IdCollection}(; zero_value=_empty_id_collection) for _ in eachindex(relations)],
        _Linear_Map{UInt32,_IdCollection}(; zero_value=_empty_id_collection),
        Vector{UInt32}(),
        node,
        UInt32(length(relations)),
        table,
        id,
    )
end

function _add_table!(indices::Vector{_ComponentRelations}, arch::_Archetype, t::_Table)
    _add_id!(arch.tables, t.id)

    if !_has_relations(arch)
        return
    end

    for (comp, target) in t.relations
        idx = indices[comp].archetypes[arch.id]
        dict = arch.index[idx]
        _add_id!(get!(() -> _IdCollection(), dict, target._id), t.id)

        target_tables = get!(() -> _IdCollection(), arch.target_tables, target._id)
        if !_contains(target_tables, t.id)
            _add_id!(target_tables, t.id)
        end
    end
end

_has_relations(a::_Archetype) = a.num_relations > 0

function _free_table!(a::_Archetype, table::_Table)
    _remove_id!(a.tables, table.id)
    push!(a.free_tables, table.id)

    # If there is only one relation, the resp. relation_tables
    # entry is removed anyway.
    if a.num_relations <= 1
        return
    end

    # TODO: can/should we be more selective here?
    for dict in a.index
        for tables in values(dict)
            _remove_id!(tables, table.id)
        end
    end
    for tables in values(a.target_tables)
        _remove_id!(tables, table.id)
    end
end

function _get_free_table!(a::_Archetype)::Tuple{UInt32,Bool}
    if isempty(a.free_tables)
        return 0, false
    end
    return pop!(a.free_tables), true
end

function _remove_target!(a::_Archetype, target::Entity)
    for dict in a.index
        delete!(dict, target._id)
    end
    delete!(a.target_tables, target._id)
end

function _reset!(a::_Archetype)
    if !_has_relations(a)
        return
    end

    for table in a.tables.ids
        push!(a.free_tables, table)
    end
    _clear!(a.tables)

    for dict in a.index
        empty!(dict)
    end
    empty!(a.target_tables)

    return
end

struct _BatchTable{M}
    table::_Table
    archetype::_Archetype{M}
    start_idx::Int
    end_idx::Int
end


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
    const index::Vector{Dict{UInt32,_IdCollection}}
    const target_tables::Dict{UInt32,_IdCollection}
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
        Vector{Dict{UInt32,_IdCollection}}(),
        Dict{UInt32,_IdCollection}(),
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
    components::Int...,
)
    _Archetype(
        Memory{Int}(collect(Int, components)),
        _IdCollection(),
        [Dict{UInt32,_IdCollection}() for _ in eachindex(relations)],
        Dict{UInt32,_IdCollection}(),
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
        if haskey(dict, target._id)
            _add_id!(dict[target._id], t.id)
        else
            dict[target._id] = _IdCollection(t.id)
        end

        if haskey(arch.target_tables, target._id)
            tables = arch.target_tables[target._id]
            if !_contains(tables, t.id)
                _add_id!(tables, t.id)
            end
        else
            arch.target_tables[target._id] = _IdCollection(t.id)
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
    start_idx::UInt32
    end_idx::UInt32
end


# A component is stored as its columns - one per table - plus the empty column that stands in
# for the tables that do not have it. The two halves live in separate containers on the world
# (see `_WorldStorage`), so there is no type pairing them: a schema names the column array
# type of each component, and the component type is its element type.
@inline _component_type(::Type{A}) where {A<:AbstractArray} = eltype(A)
@inline _storage_array_type(::Type{A}) where {A<:AbstractArray} = A

function _new_storage(::Type{S}, ::Type{C}) where {S<:Storage,C}
    _storage_type(S, C)()
end

function _new_storage(::Type{Storage{StructArray}}, ::Type{C}) where {C}
    StructArray(C)
end

function _new_storage(::Type{Storage{GPUStructArray{B}}}, ::Type{C}) where {B,C}
    GPUStructArray{B}(C)
end

function _storage_type(::Type{<:Storage{T}}, ::Type{C}) where {T,C}
    T{C}
end

function _storage_type(::Type{Storage{StructArray}}, ::Type{C}) where {C}
    _StructArray_type(C)
end

function _storage_type(::Type{Storage{GPUStructArray{B}}}, ::Type{C}) where {B,C}
    _GPUStructArray_type(C, Val{B}())
end

function _storage_type(::Type{Storage{GPUVector{B}}}, ::Type{C}) where {B,C}
    GPUVector{B,C,_gpuvector_type(C, Val{B}())}
end

# The two halves of a component storage, built separately because a world keeps them apart.
function _new_component_columns(::Type{S}, ::Type{C}) where {S<:Storage,C}
    return _storage_type(S, C)[]
end

function _new_component_empty(::Type{S}, ::Type{C}) where {S<:Storage,C}
    return _new_storage(S, C)
end

@inline function _column_or_empty(cols::Vector{A}, empty::A, table::Integer) where {A<:AbstractArray}
    return table <= length(cols) ? (@inbounds cols[table]) : empty
end

"""
    _type_vector(::Type{T})::Vector{Any} where {T<:Tuple}

Unpacks a schema type parameter into a vector of its field types.

Used by boxed worlds to move a list of types from the type domain into the value domain
without emitting one expression per type.
"""
@noinline function _type_vector(::Type{T})::Vector{Any} where {T<:Tuple}
    n = fieldcount(T)
    types = Vector{Any}(undef, n)
    for i in 1:n
        @inbounds types[i] = fieldtype(T, i)
    end
    return types
end

"""
    _new_component_relations_vector(n::Int, relation_indices::Vector{Int})

Builds the per-component relation storages of a boxed world in one runtime loop.
"""
@noinline function _new_component_relations_vector(n::Int, relation_indices::Vector{Int})
    relations = Vector{_ComponentRelations}(undef, n)
    for i in 1:n
        @inbounds relations[i] = _new_component_relations(i in relation_indices)
    end
    return relations
end

"""
    _new_columns_vector(modes::Vector{Any}, types::Vector{Any})::Vector{Any}
    _new_empties_vector(modes::Vector{Any}, types::Vector{Any})::Vector{Any}

Build the component columns, and the matching empty columns, of a boxed world.

The types arrive as values rather than as static arguments, so each one is created by a
dynamic call. That is the point: the caller does not grow a method body with one specialized
call per component type, which is what makes world construction expensive for large schemas.
"""
@noinline function _new_columns_vector(modes::Vector{Any}, types::Vector{Any})
    length(modes) == length(types) ||
        throw(ArgumentError("storage modes and component types must have the same length"))
    columns = Memory{Any}(undef, length(types))
    for i in eachindex(types)
        @inbounds columns[i] = _new_component_columns(modes[i], types[i])
    end
    return columns
end

@noinline function _new_empties_vector(modes::Vector{Any}, types::Vector{Any})
    length(modes) == length(types) ||
        throw(ArgumentError("storage modes and component types must have the same length"))
    empties = Memory{Any}(undef, length(types))
    for i in eachindex(types)
        @inbounds empties[i] = _new_component_empty(modes[i], types[i])
    end
    return empties
end

@inline function _get_component(cols::Vector{A}, arch::UInt32, row::UInt32) where {A<:AbstractArray}
    return @inbounds cols[arch][row]
end

@inline function _set_component!(
    cols::Vector{A},
    arch::UInt32,
    row::UInt32,
    value,
) where {A<:AbstractArray}
    return @inbounds cols[arch][row] = value
end

@generated function _new_storage_column(::Type{C}, ::Type{A}) where {C,A<:AbstractArray}
    if A <: GPUStructArray
        QB = QuoteNode(_gpu_backend(A))
        return :(GPUStructArray{$QB}(C))
    elseif A <: StructArray
        return :(StructArray(C))
    else
        return :(A())
    end
end

@noinline function _instantiate_column!(
    cols::Vector{A},
    empty::A,
    table::Int,
) where {C,A<:AbstractArray{C,1}}
    old_len = length(cols)
    if table > old_len
        resize!(cols, table)
        @inbounds for i in (old_len+1):table
            cols[i] = empty
        end
    end
    col = _new_storage_column(C, A)
    @inbounds cols[table] = col
    return col
end

@inline function _column_for_write!(
    cols::Vector{A},
    empty::A,
    table::Integer,
) where {C,A<:AbstractArray{C,1}}
    if table > length(cols)
        return _instantiate_column!(cols, empty, Int(table))
    end
    @inbounds col = cols[table]
    return col
end

function _activate_column!(cols::Vector{A}, empty::A, arch::Int, cap::Int) where {C,A<:AbstractArray{C,1}}
    sizehint!(_column_for_write!(cols, empty, arch), cap)
    return
end

function _clear_column!(cols::Vector{A}, empty::A, arch::UInt32) where {C,A<:AbstractArray{C,1}}
    if arch <= length(cols)
        @inbounds col = cols[arch]
        if col !== empty
            empty!(col)
        end
    end
    return
end

function _ensure_column_size!(
    cols::Vector{A},
    empty::A,
    arch::UInt32,
    needed::Int,
) where {C,A<:AbstractArray{C,1}}
    col = _column_for_write!(cols, empty, arch)
    if length(col) < needed
        resize!(col, needed)
    end
    return
end

function _move_component_data!(
    cols::Vector{A},
    old_table::UInt32,
    new_table::UInt32,
    row::UInt32,
) where {A<:AbstractArray}
    @inbounds old_vec = cols[old_table]
    @inbounds new_vec = cols[new_table]
    @inbounds push!(new_vec, old_vec[row])
    _swap_remove!(old_vec, row)
end

@generated function _move_component_data!(
    cols::Vector{A},
    old_table::UInt32,
    new_table::UInt32,
    row::UInt32,
) where {A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs_push_remove = Expr[]
    for name in names
        push!(exprs_push_remove, :(@inbounds push!(new_vec_comp.$name, old_vec_comp.$name[row])))
        push!(exprs_push_remove, :(_swap_remove!(old_vec_comp.$name, row)))
    end
    quote
        @inbounds old_vec = cols[old_table]
        @inbounds new_vec = cols[new_table]
        old_vec_comp = getfield(old_vec, :_components)
        new_vec_comp = getfield(new_vec, :_components)
        $(exprs_push_remove...)
    end
end

@generated function _copy_component_data!(
    cols::Vector{A},
    old_table::UInt32,
    new_table::UInt32,
    old_row::UInt32,
    ::CP,
) where {C,A<:AbstractArray{C,1},CP<:Val}
    # TODO: this can probably be optimized for StructArray storage
    # by moving per component instead of unpacking/packing.
    exprs = Expr[]
    push!(exprs, :(@inbounds old_vec = cols[old_table]))
    push!(exprs, :(@inbounds new_vec = cols[new_table]))

    if CP === Val{:ref} || isbitstype(C)
        # no copy required for isbits types
        if A <: _AbstractStructArray
            return quote
                _copy_component_data_per_field!(cols, old_table, new_table, old_row)
            end
        else
            push!(exprs, :(push!(new_vec, old_vec[old_row])))
        end
    elseif CP === Val{:copy} || all(isbitstype, fieldtypes(C))
        # no deep copy required for types with all isbits fields
        push!(exprs, :(push!(new_vec, _shallow_copy(old_vec[old_row]))))
    else # CP === Val{:deepcopy}
        # validity if checked before the call.
        push!(exprs, :(push!(new_vec, deepcopy(old_vec[old_row]))))
    end

    push!(exprs, Expr(:return, :nothing))

    return quote
        @inbounds begin
            $(Expr(:block, exprs...))
        end
    end
end

@generated function _copy_component_data_per_field!(
    cols::Vector{A},
    old_table::UInt32,
    new_table::UInt32,
    old_row::UInt32,
) where {A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs = Expr[]
    for name in names
        push!(exprs, :(@inbounds push!(new_vec_comp.$name, old_vec_comp.$name[old_row])))
    end
    return quote
        @inbounds old_vec = cols[old_table]
        @inbounds new_vec = cols[new_table]
        old_vec_comp = getfield(old_vec, :_components)
        new_vec_comp = getfield(new_vec, :_components)
        $(exprs...)
        return nothing
    end
end

function _copy_component_data_to_end!(
    cols::Vector{A},
    old_table::UInt32,
    new_table::UInt32,
) where {A<:AbstractArray}
    @inbounds old_vec = cols[old_table]
    @inbounds new_vec = cols[new_table]
    _copy_old_data!(new_vec, old_vec)
    return nothing
end

function _copy_old_data!(new_vec::AbstractVector, old_vec::AbstractVector)
    copyto!(new_vec, length(new_vec) - length(old_vec) + 1, old_vec, 1, length(old_vec))
end

function _copy_old_data!(new_vec::Vector, old_vec::Vector)
    unsafe_copyto!(new_vec, length(new_vec) - length(old_vec) + 1, old_vec, 1, length(old_vec))
end

function _copy_old_data!(new_vec::GPUVector, old_vec::GPUVector)
    unsafe_copyto!(new_vec, length(new_vec) - length(old_vec) + 1, old_vec, 1, length(old_vec))
end

function _copy_old_data!(new_vec::_AbstractStructArray, old_vec::_AbstractStructArray)
    unsafe_copyto!(new_vec, length(new_vec) - length(old_vec) + 1, old_vec, 1, length(old_vec))
end

function _remove_component_data!(cols::Vector{A}, arch::UInt32, row::UInt32) where {A<:AbstractArray}
    @inbounds col = cols[arch]
    _swap_remove!(col, row)
end

@generated function _remove_component_data!(
    cols::Vector{A},
    arch::UInt32,
    row::UInt32,
) where {A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs_remove = Expr[]
    for name in names
        push!(exprs_remove, :(_swap_remove!(getfield(col, :_components).$name, row)))
    end
    quote
        @inbounds col = cols[arch]
        $(exprs_remove...)
    end
end

struct _ComponentRelations
    archetypes::Vector{Int} # Relation index per archetype
    targets::Vector{Entity} # Target entity ID per table
end

function _new_component_relations(is_relation::Bool)
    if is_relation
        return _ComponentRelations(Int[0], Entity[_no_entity])
    else
        return _ComponentRelations(Int[], Entity[])
    end
end

function _add_archetype_column!(rel::_ComponentRelations)
    push!(rel.archetypes, 0)
end

function _add_table_column!(rel::_ComponentRelations)
    push!(rel.targets, _no_entity)
end

function _activate_archetype_column!(rel::_ComponentRelations, arch::Int, index::Int)
    @inbounds rel.archetypes[arch] = index
end

function _activate_table_column!(rel::_ComponentRelations, table::Int, entity::Entity)
    @inbounds rel.targets[table] = entity
end

@inline function _swap_component_data!(
    cols::Vector{A},
    arch::UInt32,
    i::Int,
    j::Int,
) where {A<:AbstractArray}
    @inbounds col = cols[arch]
    _swap_indices!(col, i, j)
end

@generated function _swap_component_data!(
    cols::Vector{A},
    arch::UInt32,
    i::Int,
    j::Int,
) where {A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs_swap = Expr[]
    for name in names
        push!(exprs_swap, :(_swap_indices!(getfield(col, :_components).$name, i, j)))
    end
    quote
        @inbounds col = cols[arch]
        $(exprs_swap...)
    end
end

@inline @generated function _permute_component_cycle!(
    cols::Vector{A},
    table::UInt32,
    entities::Entities,
    entity_index::Vector{_EntityIndex},
    start::Int,
) where {A<:AbstractArray}
    names = fieldnames(eltype(A))

    if A <: _AbstractStructArray
        tmp_syms = Symbol[gensym(:tmp) for _ in names]

        tmp_exprs = Expr[
            :(@inbounds $(tmp_syms[i]) = getfield(comps, $(QuoteNode(names[i])))[start]) for i in eachindex(names)
        ]

        shift_exprs = Expr[
            :(getfield(comps, $(QuoteNode(name)))[row] = getfield(comps, $(QuoteNode(name)))[next_row]) for
            name in names
        ]

        final_exprs = Expr[
            :(getfield(comps, $(QuoteNode(names[i])))[row] = $(tmp_syms[i])) for i in eachindex(names)
        ]
    else
        tmp_exprs = Expr[:(@inbounds tmp = col[start])]

        shift_exprs = Expr[:(col[row] = col[next_row])]

        final_exprs = Expr[:(col[row] = tmp)]
    end

    return quote
        @inbounds col = cols[table]
        $(A <: _AbstractStructArray ? :(comps = getfield(col, :_components)) : (:(nothing)))

        $(tmp_exprs...)

        row = start

        @inbounds while true
            entity = entities[row]
            index = entity_index[entity._id]
            next_row = Int(index.row)

            entity_index[entity._id] = _EntityIndex(UInt32(0), index.row)

            if next_row == start
                $(final_exprs...)
                break
            end

            $(shift_exprs...)

            row = next_row
        end

        return nothing
    end
end


struct _ComponentStorage{C,A<:AbstractArray{C,1}}
    primary::Vector{A}
    extra::Vector{Vector{A}}
    empty_column::A
end

@inline _component_type(::Type{<:_ComponentStorage{C}}) where {C} = C
@inline _storage_array_type(::Type{<:_ComponentStorage{C,A}}) where {C,A} = A

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

function _new_component_storage(::Type{S}, ::Type{C}) where {S<:Storage,C}
    empty_col = _new_storage(S, C)
    return _ComponentStorage{C,typeof(empty_col)}(
        [empty_col],
        [Vector{typeof(empty_col)}()],
        empty_col,
    )
end

@inline function _column(
    storage::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
) where {C,A}
    @inbounds if local_table == 1
        return storage.primary[Int(arch_id)]
    else
        return storage.extra[Int(arch_id)][Int(local_table) - 1]
    end
end

@inline function _get_component(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    row::UInt32,
    ::Val{false},
) where {C,A<:AbstractArray}
    @inbounds if local_table == 1
        col = s.primary[Int(arch_id)]
        if length(col) == 0
            throw(ArgumentError(lazy"entity has no $C component"))
        end
        return @inbounds col[row]
    end
    return @inbounds s.extra[Int(arch_id)][Int(local_table) - 1][row]
end

@inline function _get_component(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    row::UInt32,
    ::Val{true},
) where {C,A<:AbstractArray}
    @inbounds col = _column(s, arch_id, local_table)
    return @inbounds col[row]
end

@inline function _set_component!(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    row::UInt32,
    value::C,
    ::Val{false},
) where {C,A<:AbstractArray}
    @inbounds if local_table == 1
        col = s.primary[Int(arch_id)]
        if length(col) == 0
            throw(ArgumentError(lazy"entity has no $C component"))
        end
        return @inbounds col[row] = value
    end
    return @inbounds s.extra[Int(arch_id)][Int(local_table) - 1][row] = value
end

@inline function _set_component!(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    row::UInt32,
    value::C,
    ::Val{true},
) where {C,A<:AbstractArray}
    @inbounds col = _column(s, arch_id, local_table)
    return @inbounds col[row] = value
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

function _add_archetype_slot!(storage::_ComponentStorage{C,A}) where {C,A}
    push!(storage.primary, storage.empty_column)
    push!(storage.extra, Vector{A}())
    return nothing
end

function _activate_archetype_storage_for_comp!(
    storage::_ComponentStorage{C,A},
    arch_id::UInt32,
    cap::Int,
) where {C,A<:AbstractArray}
    primary = _new_storage_column(C, A)
    sizehint!(primary, cap)

    @inbounds storage.primary[Int(arch_id)] = primary
    @inbounds storage.extra[Int(arch_id)] = Vector{A}()
    return nothing
end

function _create_column!(
    storage::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    cap::Int,
) where {C,A<:AbstractArray}
    if local_table == 1
        @inbounds col = storage.primary[Int(arch_id)]
        @assert col !== storage.empty_column
        sizehint!(col, cap)
        return nothing
    end

    col = _new_storage_column(C, A)
    sizehint!(col, cap)

    @inbounds extras = storage.extra[Int(arch_id)]
    @assert Int(local_table) - 1 == length(extras) + 1

    push!(extras, col)
    return nothing
end

function _clear_column!(
    storage::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
) where {C,A<:AbstractArray}
    col = _column(storage, arch_id, local_table)
    empty!(col)
    return nothing
end

function _ensure_column_size!(
    storage::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    needed::Int,
) where {C,A<:AbstractArray}
    @inbounds col = _column(storage, arch_id, local_table)
    if length(col) < needed
        resize!(col, needed)
    end
    return nothing
end

function _move_component_data!(
    s::_ComponentStorage{C,A},
    old_arch::UInt32,
    old_local::UInt32,
    new_arch::UInt32,
    new_local::UInt32,
    row::UInt32,
) where {C,A<:AbstractArray}
    @inbounds old_vec = _column(s, old_arch, old_local)
    @inbounds new_vec = _column(s, new_arch, new_local)
    @inbounds push!(new_vec, old_vec[row])
    _swap_remove!(old_vec, row)
end

@generated function _move_component_data!(
    s::_ComponentStorage{C,A},
    old_arch::UInt32,
    old_local::UInt32,
    new_arch::UInt32,
    new_local::UInt32,
    row::UInt32,
) where {C,A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs_push_remove = Expr[]
    for name in names
        push!(exprs_push_remove, :(@inbounds push!(new_vec_comp.$name, old_vec_comp.$name[row])))
        push!(exprs_push_remove, :(_swap_remove!(old_vec_comp.$name, row)))
    end
    quote
        @inbounds old_vec = _column(s, old_arch, old_local)
        @inbounds new_vec = _column(s, new_arch, new_local)
        old_vec_comp = getfield(old_vec, :_components)
        new_vec_comp = getfield(new_vec, :_components)
        $(exprs_push_remove...)
    end
end

@generated function _copy_component_data!(
    s::_ComponentStorage{C,A},
    old_arch::UInt32,
    old_local::UInt32,
    new_arch::UInt32,
    new_local::UInt32,
    old_row::UInt32,
    ::CP,
) where {C,A<:AbstractArray,CP<:Val}
    exprs = Expr[]
    push!(exprs, :(@inbounds old_vec = _column(s, old_arch, old_local)))
    push!(exprs, :(@inbounds new_vec = _column(s, new_arch, new_local)))

    if CP === Val{:ref} || isbitstype(C)
        if A <: _AbstractStructArray
            return quote
                _copy_component_data_per_field!(
                    s, old_arch, old_local, new_arch, new_local, old_row,
                )
            end
        else
            push!(exprs, :(push!(new_vec, old_vec[old_row])))
        end
    elseif CP === Val{:copy} || all(isbitstype, fieldtypes(C))
        push!(exprs, :(push!(new_vec, _shallow_copy(old_vec[old_row]))))
    else
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
    s::_ComponentStorage{C,A},
    old_arch::UInt32,
    old_local::UInt32,
    new_arch::UInt32,
    new_local::UInt32,
    old_row::UInt32,
) where {C,A<:_AbstractStructArray}
    names = fieldnames(C)
    exprs = Expr[]
    for name in names
        push!(exprs, :(@inbounds push!(new_vec_comp.$name, old_vec_comp.$name[old_row])))
    end
    return quote
        @inbounds old_vec = _column(s, old_arch, old_local)
        @inbounds new_vec = _column(s, new_arch, new_local)
        old_vec_comp = getfield(old_vec, :_components)
        new_vec_comp = getfield(new_vec, :_components)
        $(exprs...)
        return nothing
    end
end

function _copy_component_data_to_end!(
    s::_ComponentStorage{C,A},
    old_arch::UInt32,
    old_local::UInt32,
    new_arch::UInt32,
    new_local::UInt32,
) where {C,A<:AbstractArray}
    @inbounds old_vec = _column(s, old_arch, old_local)
    @inbounds new_vec = _column(s, new_arch, new_local)
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

function _remove_component_data!(s::_ComponentStorage{C,A}, arch_id::UInt32, local_table::UInt32, row::UInt32) where {C,A<:AbstractArray}
    @inbounds col = _column(s, arch_id, local_table)
    _swap_remove!(col, row)
end

@generated function _remove_component_data!(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    row::UInt32,
) where {C,A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs_remove = Expr[]
    for name in names
        push!(exprs_remove, :(_swap_remove!(getfield(col, :_components).$name, row)))
    end
    quote
        @inbounds col = _column(s, arch_id, local_table)
        $(exprs_remove...)
    end
end

struct _ComponentRelations
    archetypes::Vector{Int}
    targets::Vector{Entity}
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
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    i::Int,
    j::Int,
) where {C,A<:AbstractArray}
    @inbounds col = _column(s, arch_id, local_table)
    _swap_indices!(col, i, j)
end

@generated function _swap_component_data!(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    i::Int,
    j::Int,
) where {C,A<:_AbstractStructArray}
    names = fieldnames(eltype(A))
    exprs_swap = Expr[]
    for name in names
        push!(exprs_swap, :(_swap_indices!(getfield(col, :_components).$name, i, j)))
    end
    quote
        @inbounds col = _column(s, arch_id, local_table)
        $(exprs_swap...)
    end
end

@inline @generated function _permute_component_cycle!(
    s::_ComponentStorage{C,A},
    arch_id::UInt32,
    local_table::UInt32,
    entities::Entities,
    entity_index::Vector{_EntityIndex},
    start::Int,
) where {C,A<:AbstractArray}
    names = fieldnames(C)

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
        @inbounds col = _column(s, arch_id, local_table)
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

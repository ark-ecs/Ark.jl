
struct _ComponentStorage{C,A<:AbstractArray{C,1}}
    data::Vector{A}
end

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

function _get_component(s::_ComponentStorage{C,A}, arch::UInt32, row::UInt32) where {C,A<:AbstractArray}
    @inbounds col = s.data[arch]
    if length(col) == 0
        throw(ArgumentError(lazy"entity has no $C component"))
    end
    return @inbounds col[row]
end

function _set_component!(s::_ComponentStorage{C,A}, arch::UInt32, row::UInt32, value::C) where {C,A<:AbstractArray}
    @inbounds col = s.data[arch]
    if length(col) == 0
        throw(ArgumentError(lazy"entity has no $C component"))
    end
    return @inbounds col[row] = value
end

@generated function _add_column!(storage::_ComponentStorage{C,A}) where {C,A<:AbstractArray}
    if A <: GPUStructArray
        QB = QuoteNode(A.parameters[1])
        return :(push!(storage.data, GPUStructArray{$QB}(C)))
    elseif A <: StructArray
        return :(push!(storage.data, StructArray(C)))
    else
        return :(push!(storage.data, A()))
    end
end

function _activate_column!(storage::_ComponentStorage{C,A}, arch::Int, cap::Int) where {C,A<:AbstractArray}
    sizehint!(storage.data[arch], cap)
end

function _clear_column!(storage::_ComponentStorage{C,A}, arch::UInt32) where {C,A<:AbstractArray}
    empty!(storage.data[arch])
end

function _ensure_column_size!(storage::_ComponentStorage{C,A}, arch::UInt32, needed::Int) where {C,A<:AbstractArray}
    @inbounds col = storage.data[arch]
    if length(col) < needed
        resize!(col, needed)
    end
    return
end

function _move_component_data!(
    s::_ComponentStorage{C,A},
    old_table::UInt32,
    new_table::UInt32,
    row::UInt32,
) where {C,A<:AbstractArray}
    @inbounds old_vec = s.data[old_table]
    @inbounds new_vec = s.data[new_table]
    @inbounds push!(new_vec, old_vec[row])
    _swap_remove!(old_vec, row)
end

@generated function _move_component_data!(
    s::_ComponentStorage{C,A},
    old_table::UInt32,
    new_table::UInt32,
    row::UInt32,
) where {C,A<:StructArray}
    names = fieldnames(A.parameters[1])
    exprs_push_remove = Expr[]
    for name in names
        push!(exprs_push_remove, :(@inbounds push!(new_vec_comp.$name, old_vec_comp.$name[row])))
        push!(exprs_push_remove, :(_swap_remove!(old_vec_comp.$name, row)))
    end
    quote
        @inbounds old_vec = s.data[old_table]
        @inbounds new_vec = s.data[new_table]
        old_vec_comp = getfield(old_vec, :_components)
        new_vec_comp = getfield(new_vec, :_components)
        $(exprs_push_remove...)
    end
end

@generated function _copy_component_data!(
    s::_ComponentStorage{C,A},
    old_table::UInt32,
    new_table::UInt32,
    old_row::UInt32,
    ::CP,
) where {C,A<:AbstractArray,CP<:Val}
    # TODO: this can probably be optimized for StructArray storage
    # by moving per component instead of unpacking/packing.
    exprs = []
    push!(exprs, :(@inbounds old_vec = s.data[old_table]))
    push!(exprs, :(@inbounds new_vec = s.data[new_table]))

    if CP === Val{:ref} || isbitstype(C)
        # no copy required for isbits types
        push!(exprs, :(push!(new_vec, old_vec[old_row])))
    elseif CP === Val{:copy} || all(T -> isbitstype(T), fieldtypes(C))
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

function _copy_component_data_to_end!(
    s::_ComponentStorage{C,A},
    old_table::UInt32,
    new_table::UInt32,
) where {C,A<:AbstractArray}
    @inbounds old_vec = s.data[old_table]
    @inbounds new_vec = s.data[new_table]
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

function _remove_component_data!(s::_ComponentStorage{C,A}, arch::UInt32, row::UInt32) where {C,A<:AbstractArray}
    @inbounds col = s.data[arch]
    _swap_remove!(col, row)
end

@generated function _remove_component_data!(
    s::_ComponentStorage{C,A},
    arch::UInt32,
    row::UInt32,
) where {C,A<:StructArray}
    names = fieldnames(A.parameters[1])
    exprs_remove = Expr[]
    for name in names
        push!(exprs_remove, :(_swap_remove!(getfield(col, :_components).$name, row)))
    end
    quote
        @inbounds col = s.data[arch]
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

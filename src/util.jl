
_swap!(v::AbstractArray, i, j) = @inbounds v[i] = v[j]

@inline function _swap_indices!(v::AbstractArray, i, j)
    @inbounds v[i], v[j] = v[j], v[i]
    return
end

@inline function _swap_remove!(v::AbstractArray, i::UInt32)::Bool
    last_index = length(v)
    swapped = i != last_index
    if swapped
        _swap!(v, i, last_index)
    end
    pop!(v)
    return swapped
end

function _type_parameter(::Type{Type{T}}) where {T}
    return T
end

function _val_parameter(::Type{Val{T}}) where {T}
    return T
end

function _pair_first_type(::Type{<:Pair{T}}) where {T}
    return T
end

@inline function _to_types(::Type{TS})::Vector{DataType} where {TS<:Tuple}
    return DataType[_unwrap_const_type(_val_parameter(x)) for x in fieldtypes(TS)]
end

@inline function _to_types(::Type{Val{TS}})::Vector{DataType} where {TS<:Tuple}
    return DataType[_unwrap_const_type(x <: Val ? _val_parameter(x) : x) for x in fieldtypes(TS)]
end

@inline function _to_types(::Type{Val{V}})::Vector{DataType} where {V<:Val}
    return _to_types(V)
end

@inline function _to_types(types::Tuple)::Vector{DataType}
    return DataType[_unwrap_const_type(x) for x in types]
end

function _unwrap_relation_type(::Type{Relation{T}}) where {T}
    return T
end

function _unwrap_relation_type(::Type{T}) where {T}
    return T
end

function _declares_relation(::Type{Relation{T}}) where {T}
    return true
end

function _declares_relation(::Type{T}) where {T}
    return false
end

@inline function _is_relation_type(::Type{T}, declared_relations::Type{<:Tuple})::Bool where {T}
    for relation_type in fieldtypes(declared_relations)
        if T === relation_type
            return true
        end
    end
    return false
end

@inline function _check_relations(types::Vector{DataType}, declared_relations::Type{<:Tuple})
    for T in types
        if !_is_relation_type(T, declared_relations)
            throw(ArgumentError("component $(nameof(T)) is not a relationship"))
        end
    end
end

@inline function _check_is_subset(subset::Vector{DataType}, types::Vector{DataType})
    if !isempty(setdiff(subset, types))
        # TODO: improve error message
        throw(ArgumentError("all relations must be in the set of component types"))
    end
end

@inline function _check_no_duplicates(types::Vector{DataType})
    unique_types = unique(types)
    if length(types) != length(unique_types)
        duplicates = DataType[x for x in unique_types if count(==(x), types) > 1]
        names = join(Symbol[nameof(x) for x in duplicates], ", ")
        throw(ArgumentError("duplicate component types: $names"))
    end
end

@inline function _check_if_intersect(types_1::Vector{DataType}, types_2::Vector{DataType})
    if !isempty(intersect(types_1, types_2))
        throw(ArgumentError("component added and removed in the same exchange operation"))
    end
end

# TODO: improve the heuristic with something more robust, as of 1.12 though Julia doesn't
# expose anything to set the flag more correctly
function _is_testing()
    pname = Base.active_project()
    isnothing(pname) ? false : (contains(pname, "tmp/jl_") || contains(pname, "Temp\\jl_"))
end

const _DEBUG = _is_testing() ? "true" : @load_preference("DEBUG", default = "false")

macro check(arg)
    _DEBUG == "true" ? esc(:(@assert $arg)) : nothing
end

function _format_type(::Type{Type{T}}) where {T}
    return _format_type(T)
end

function _format_type(T::Type)
    params = T.parameters
    name = string(nameof(T))
    isempty(params) && return name
    return string(name, "{", join(map(_format_type_parameter, params), ", "), "}")
end

function _format_type(T)
    return string(T)
end

function _format_type_parameter(T::Type)
    return _format_type(T)
end

function _format_type_parameter(x)
    return sprint(show, x)
end

@generated function _shallow_copy(x::T) where T
    if T == Symbol || T == String
        return :(x)
    end
    n = fieldcount(T)
    field_exprs = Expr[:(getfield(x, $i)) for i in 1:n]
    return Expr(:new, T, field_exprs...)
end

function _generate_component_switch(comp_idx_sym::Symbol, call_exprs::Vector{Expr})
    exprs = Expr[]
    for (i, call_expr) in enumerate(call_exprs)
        push!(exprs, :(
            if $comp_idx_sym == $i
                return $call_expr
            end
        ))
    end
    return Expr(:block, exprs...)
end

@inline function _to_requested_types(::Type{TS})::Vector{Any} where {TS<:Tuple}
    return [x <: Val ? _val_parameter(x) : x for x in fieldtypes(TS)]
end

function _component_index(CS::Type{<:Tuple}, TargetType::Type)::Union{Int,Nothing}
    TargetType = _unwrap_const_type(TargetType)
    _storage_types = fieldtypes(CS)
    for (i, S) in enumerate(_storage_types)
        if S <: _ComponentStorage && _component_type(S) === TargetType
            return i
        end
    end
    return throw(ArgumentError(lazy"Component type $(TargetType) not found in the World"))
end

function _has_relations(declared_relations::Type{<:Tuple})
    return fieldcount(declared_relations) > 0
end

@inline @generated function _relation_types_and_targets(
    relations::Tuple{Vararg{Any,N}},
) where {N}
    rel_types = Expr(:tuple)
    targets = Expr(:tuple)

    for i in 1:N
        push!(rel_types.args, :(Val(getfield(getfield(relations, $i), :first))))
        push!(targets.args, :(getfield(getfield(relations, $i), :second)))
    end

    return quote
        return $rel_types, $targets
    end
end

@inline @generated function _valtuple(t::Tuple{Vararg{Any,N}}) where {N}
    exprs = Expr[:(Val(getfield(t, $i))) for i in 1:N]
    return Expr(:tuple, exprs...)
end


_swap!(v::AbstractArray, i, j) = @inbounds v[i] = v[j]

@inline function _swap_remove!(v::AbstractArray, i::UInt32)::Bool
    last_index = length(v)
    swapped = i != last_index
    if swapped
        _swap!(v, i, last_index)
    end
    pop!(v)
    return swapped
end

@inline function _to_types(::Type{TS})::Vector{DataType} where {TS<:Tuple}
    return [x.parameters[1] for x in TS.parameters]
end

@inline function _to_types(::Type{Val{TS}})::Vector{DataType} where {TS<:Tuple}
    return [x <: Val ? x.parameters[1] : x for x in TS.parameters]
end

@inline function _to_types(::Type{Val{V}})::Vector{DataType} where {V<:Val}
    return _to_types(V)
end

@inline function _to_types(vec::Core.SimpleVector)::Vector{DataType}
    return collect(vec)
end

@inline function _check_relations(types::Vector{DataType})
    for T in types
        if !(T <: Relationship)
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
        duplicates = [x for x in unique_types if count(==(x), types) > 1]
        names = join(map(nameof, duplicates), ", ")
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

function _format_type(T)
    if T isa Type && T <: Type
        return _format_type(T.parameters[1])
    elseif T isa DataType && isempty(T.parameters)
        return string(nameof(T))
    elseif T isa DataType
        return string(nameof(T), "{", join(map(_format_type, T.parameters), ", "), "}")
    else
        return string(T)
    end
end

@generated function _shallow_copy(x::T) where T
    names = fieldnames(T)
    field_exprs = [:($(name) = x.$name) for name in names]

    return quote
        return $(Expr(:new, T, field_exprs...))
    end
end

function _generate_component_switch(CS::Type{<:Tuple}, comp_idx_sym::Symbol, func_generator::Function)
    N = length(CS.parameters)
    exprs = Expr[]
    for i in 1:N
        call_expr = func_generator(i)
        push!(exprs, :(
            if $comp_idx_sym == $i
                return $call_expr
            end
        ))
    end
    return Expr(:block, exprs...)
end

function _generate_type_lookup(CS::Type{<:Tuple}, TargetType::Type, result_generator::Function)
    _storage_types = CS.parameters
    for (i, S) in enumerate(_storage_types)
        if S <: _ComponentStorage && S.parameters[1] === TargetType
            return result_generator(i)
        end
    end
    return :(throw(ArgumentError($(lazy"Component type $(TargetType) not found in the World"))))
end

function _has_relations(CS::Type{<:Tuple})
    _storage_types = CS.parameters
    for (i, S) in enumerate(_storage_types)
        if S.parameters[1] <: Relationship
            return true
        end
    end
    return false
end

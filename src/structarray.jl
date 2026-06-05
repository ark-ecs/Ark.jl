"""
    StructArray

A custom implementation of a StructArray similar to the one exported by StructArrays.jl.

In the interface, it is only used to mark that a component has a struct array storage
with `ComponentA => Storage{StructArray}`.
"""
struct StructArray{C,CS<:NamedTuple,N} <: _AbstractStructArray{C,CS,N}
    _components::CS
end

function StructArray(tp::Type{C}) where {C}
    _StructArray_from_type(tp)
end

@generated function _StructArray_from_type(::Type{C}) where {C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("StructArray storage not allowed for components without fields")

    vec_types = Expr[:(Vector{$t}) for t in types]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})
    kv_exprs = Expr[:($name = Vector{$t}()) for (name, t) in zip(names, types)]

    return quote
        StructArray{C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _StructArray_type(::Type{C}) where {C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("StructArray storage not allowed for components without fields")

    vec_types = Expr[:(Vector{$t}) for t in types]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})

    return quote
        StructArray{C,$nt_type,$num_fields}
    end
end

@generated function _StructArrayView_type(::Type{C}, ::Type{I}) where {C,I<:AbstractUnitRange{T}} where {T<:Integer}
    names = fieldnames(C)
    types = fieldtypes(C)

    subarray_types = Expr[:(SubArray{$t,1,Vector{$t},Tuple{I},true}) for t in types]
    nt_type = :(NamedTuple{
        $names,
        Tuple{$(subarray_types...)},
    })
    return quote
        _StructArrayView{C,$nt_type}
    end
end

@generated function Base.view(
    sa::S,
    idx::I,
) where {S<:StructArray{C,CS,N},I<:AbstractUnitRange{T}} where {C,CS<:NamedTuple,N,T<:Integer}
    names = fieldnames(C)
    vec_types = fieldtypes(CS)
    view_exprs = Expr[:($name = @view getfield(sa, :_components).$name[idx]) for name in names]
    subarray_types = Expr[:(SubArray{$(eltype(vt)),1,$vt,Tuple{I},true}) for vt in vec_types]
    nt_type = :(NamedTuple{$names,Tuple{$(subarray_types...)}})
    return quote
        _StructArrayView{C,$nt_type}((; $(view_exprs...)))
    end
end

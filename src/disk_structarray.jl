"""
    DiskStructArray

A disk-backed StructArray that stores each component field in a [`DiskVector`](@ref).

As for `DiskVector`, backing files are managed by Ark and deleted automatically
when the storage is garbage-collected or at process exit. All component fields
must be isbits types with nonzero size.

# Examples

```julia
world = World(
    Position => Storage{DiskStructArray},
    Velocity => Storage{DiskStructArray},
)
```
"""
struct DiskStructArray{C,CS<:NamedTuple,N} <: _AbstractStructArray{C,CS,N}
    _components::CS
end

function _check_diskstructarray_type(::Type{C}) where {C}
    if fieldcount(C) == 0
        throw(ArgumentError("DiskStructArray storage not allowed for components without fields"))
    end
    for t in fieldtypes(C)
        _check_diskvector_eltype(t)
    end
    return nothing
end

function DiskStructArray(tp::Type{C}) where {C}
    _DiskStructArray_from_type(tp)
end

@generated function _DiskStructArray_from_type(::Type{C}) where {C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    vec_types = Expr[:(DiskVector{$t}) for t in types]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})
    kv_exprs = Expr[:($name = DiskVector{$t}()) for (name, t) in zip(names, types)]
    return quote
        _check_diskstructarray_type(C)
        DiskStructArray{C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _DiskStructArray_type(::Type{C}) where {C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    vec_types = Expr[:(DiskVector{$t}) for t in types]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})
    return quote
        DiskStructArray{C,$nt_type,$num_fields}
    end
end

@generated function _DiskStructArrayView_type(::Type{C}, ::Type{I}) where {C,I<:AbstractUnitRange{T}} where {T<:Integer}
    names = fieldnames(C)
    types = fieldtypes(C)
    subarray_types = Expr[:(SubArray{$t,1,DiskVector{$t},Tuple{I},true}) for t in types]
    nt_type = :(NamedTuple{
        $names,
        Tuple{$(subarray_types...)},
    })
    return quote
        StructArrayView{C,$nt_type}
    end
end

@generated function Base.view(
    sa::S,
    idx::I,
) where {S<:DiskStructArray{C,CS,N},I<:AbstractUnitRange{T}} where {C,CS<:NamedTuple,N,T<:Integer}
    names = fieldnames(C)
    vec_types = fieldtypes(CS)
    view_exprs = Expr[:($name = @view getfield(sa, :_components).$name[idx]) for name in names]
    subarray_types = Expr[:(SubArray{$(eltype(vt)),1,$vt,Tuple{I},true}) for vt in vec_types]
    nt_type = :(NamedTuple{$names,Tuple{$(subarray_types...)}})
    return quote
        StructArrayView{C,$nt_type}((; $(view_exprs...)))
    end
end

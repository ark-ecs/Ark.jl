
@generated function _FieldsViewable_type(::Type{A}) where {A<:AbstractArray{T,N}} where {T,N}
    return :(FieldViewable{$T,$N,$A})
end

"""
    unpack(a::FieldViewable)

Unpacks the components (i.e. field vectors) of a column returned from a [Query](@ref)
when the storage is different from `Storage{StructArray}`.
See also [@unpack](@ref).

!!! note

    Setting values on unpacked non-isbits fields of immutable components has a certain overhead,
    as the underlying struct needs to be reconstructed and written to memory. See
"""
@generated function unpack(v::FieldViewable{T}) where {T}
    props = fieldnames(T)
    exprs = [:(FieldView{$(QuoteNode(p))}(v)) for p in props]
    return :(tuple($(exprs...)))
end

unpack(a::SubArray) = a

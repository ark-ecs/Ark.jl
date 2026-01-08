
"""
    StructArray

A custom implementation of a StructArray similar to the one exported by StructArrays.jl.

In the interface, it is only used to mark that a component has a struct array storage
with `ComponentA => Storage{StructArray}`.
"""
struct StructArray{C,CS<:NamedTuple,N} <: _AbstractStructArray{C}
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

    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :(Vector{$t}), types)...)}})
    kv_exprs = [:($name = Vector{$t}()) for (name, t) in zip(names, types)]

    return quote
        StructArray{C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _StructArray_type(::Type{C}) where {C}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("StructArray storage not allowed for components without fields")

    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(map(t -> :(Vector{$t}), types)...)}})

    return quote
        StructArray{C,$nt_type,$num_fields}
    end
end

@generated function _StructArrayView_type(::Type{C}, ::Type{I}) where {C,I<:AbstractUnitRange{T}} where {T<:Integer}
    names = fieldnames(C)
    types = fieldtypes(C)

    nt_type = :(NamedTuple{
        ($(map(QuoteNode, names)...),),
        Tuple{$(map(t -> :(SubArray{$t,1,Vector{$t},Tuple{I},true}), types)...)},
    })
    return quote
        _StructArrayView{C,$nt_type,I}
    end
end

@generated function Base.getproperty(sa::StructArray{C}, name::Symbol) where {C}
    component_names = fieldnames(C)
    cases = [
        :(name === $(QuoteNode(n)) && return getfield(sa, :_components).$n) for n in component_names
    ]
    return Expr(:block, cases..., :(throw(ErrorException(lazy"type $C has no field $name"))))
end

@generated function Base.resize!(sa::StructArray{C}, n::Integer) where {C}
    names = fieldnames(C)
    resize_exprs = [
        :(resize!(getfield(sa, :_components).$name, n)) for name in names
    ]
    return Expr(:block, resize_exprs..., :(sa))
end

@generated function Base.sizehint!(sa::StructArray{C}, n::Integer) where {C}
    names = fieldnames(C)
    sizehint_exprs = [
        :(sizehint!(getfield(sa, :_components).$name, n)) for name in names
    ]
    return Expr(:block, sizehint_exprs..., :(sa))
end

@generated function Base.push!(sa::StructArray{C}, c::C) where {C}
    names = fieldnames(C)
    push_exprs = [
        :(push!(getfield(sa, :_components).$name, c.$name)) for name in names
    ]
    return Expr(:block, push_exprs..., :(sa))
end

@generated function Base.pop!(sa::StructArray{C}) where {C}
    names = fieldnames(C)
    pop_exprs = [
        :(pop!(getfield(sa, :_components).$name)) for name in names
    ]
    return Expr(:block, pop_exprs..., :(sa))
end

@generated function Base.fill!(sa::StructArray{C}, value::C) where {C}
    names = fieldnames(C)
    fill_exprs = [
        :(fill!(getfield(sa, :_components).$name, value.$name)) for name in names
    ]
    return Expr(:block, fill_exprs..., :(sa))
end

Base.view(sa::StructArray, ::Colon) = view(sa, 1:length(sa))

@generated function Base.view(
    sa::S,
    idx::I,
) where {S<:StructArray{C,CS,N},I<:AbstractUnitRange{T}} where {C,CS<:NamedTuple,N,T<:Integer}
    names = fieldnames(C)
    types = fieldtypes(C)
    view_exprs = [
        :($name = @view getfield(sa, :_components).$name[idx]) for name in names
    ]
    nt_type = :(NamedTuple{
        ($(map(QuoteNode, names)...),),
        Tuple{$(map(t -> :(SubArray{$t,1,Vector{$t},Tuple{I},true}), types)...)},
    })
    return quote
        _StructArrayView{C,$nt_type,I}((; $(view_exprs...)), idx)
    end
end

Base.@propagate_inbounds @generated function Base.getindex(sa::StructArray{C}, i::Int) where {C}
    names = fieldnames(C)
    field_exprs = [
        :($(name) = getfield(sa, :_components).$name[i]) for name in names
    ]
    return Expr(:block, Expr(:new, C, field_exprs...))
end

Base.@propagate_inbounds @generated function Base.setindex!(sa::StructArray{C}, c, i::Int) where {C}
    names = fieldnames(C)
    set_exprs = [
        :(getfield(sa, :_components).$name[i] = c.$name) for name in names
    ]
    return Expr(:block, set_exprs..., :(nothing))
end

Base.@propagate_inbounds function Base.iterate(sa::StructArray{C}) where {C}
    length(sa) == 0 && return nothing
    return sa[1], 2
end

Base.@propagate_inbounds function Base.iterate(sa::StructArray{C}, i::Int) where {C}
    i > length(sa) && return nothing
    return sa[i], i + 1
end

Base.empty!(sa::StructArray) = resize!(sa, 0)
Base.length(sa::StructArray) = length(first(getfield(sa, :_components)))
Base.size(sa::StructArray) = (length(sa),)
Base.eachindex(sa::StructArray) = 1:length(sa)
Base.eltype(::Type{<:StructArray{C}}) where {C} = C
Base.IndexStyle(::Type{<:StructArray}) = IndexLinear()

function Base.firstindex(sa::StructArray)
    # Do not simplify to this, as it is then not covered by the tests for some reason:
    # Base.firstindex(sa::StructArray) = 1
    return 1
end

Base.lastindex(sa::StructArray) = length(sa)

struct _StructArrayView{C,CS<:NamedTuple,I} <: AbstractArray{C,1}
    _components::CS
    _indices::I
end

Base.@propagate_inbounds @generated function Base.getindex(sa::_StructArrayView{C}, i::Int) where {C}
    names = fieldnames(C)
    field_exprs = [
        :($(name) = getfield(sa, :_components).$name[i]) for name in names
    ]
    return Expr(:block, Expr(:new, C, field_exprs...))
end

Base.@propagate_inbounds @generated function Base.setindex!(sa::_StructArrayView{C}, c::C, i::Int) where {C}
    names = fieldnames(C)
    set_exprs = [
        :(getfield(sa, :_components).$name[i] = c.$name) for name in names
    ]
    return Expr(:block, set_exprs..., :(sa))
end

@generated function Base.fill!(sa::_StructArrayView{C}, value::C) where {C}
    names = fieldnames(C)
    fill_exprs = [
        :(fill!(getfield(sa, :_components).$name, value.$name)) for name in names
    ]
    return Expr(:block, fill_exprs..., :(sa))
end

Base.@propagate_inbounds function Base.iterate(sa::_StructArrayView)
    length(sa) == 0 && return nothing
    return sa[1], 2
end

Base.@propagate_inbounds function Base.iterate(sa::_StructArrayView, i::Int)
    i > length(sa) && return nothing
    return sa[i], i + 1
end

Base.size(sa::_StructArrayView) = (length(sa._indices),)
Base.length(sa::_StructArrayView) = length(sa._indices)
Base.eltype(::Type{<:_StructArrayView{C}}) where {C} = C
Base.IndexStyle(::Type{<:_StructArrayView}) = IndexLinear()
Base.eachindex(sa::_StructArrayView) = 1:length(sa)

function Base.firstindex(sa::_StructArrayView)
    # Do not simplify to this, as it is then not covered by the tests for some reason:
    # Base.firstindex(sa::StructArray) = 1
    return 1
end

Base.lastindex(sa::_StructArrayView) = length(sa)

function Base.show(io::IO, a::_StructArrayView{C,CS}) where {C,CS<:NamedTuple}
    names = CS.parameters[1]
    types = CS.parameters[2].parameters

    fields = map(((n, t),) -> "$(n)::SubArray{$(_format_type(t.parameters[1]))}", zip(names, types))
    fields_string = join(fields, ", ")

    eltype_name = _format_type(C)
    print(io, "$(length(a))-element StructArrayView($fields_string) with eltype $eltype_name")
    if length(a) < 12
        for el in a
            print(io, "\n $el")
        end
        print(io, "\n")
    else
        for el in a[1:5]
            print(io, "\n $el")
        end
        print(io, "\n ⋮")
        for el in a[(end-4):end]
            print(io, "\n $el")
        end
        print(io, "\n")
    end
end

"""
    unpack(a::_StructArrayView)

Unpacks the components (i.e. field vectors) of a `StructArray` column returned from a [Query](@ref).
See also [@unpack](@ref).
"""
unpack(a::_StructArrayView) = a._components

"""
    @unpack ...

Unpacks the tuple returned from a [Query](@ref) during iteration into field vectors.
Field vectors are particularly useful when the component is stored in a `StructArray`,
but can also be used with other storages, although those are currently not
equally efficient in broadcasted operations.

Columns for components without fields, like primitives or label components, fall through `@unpack` unaltered.

See also [unpack(::_StructArrayView)](@ref) and [unpack(::FieldViewable)](@ref).

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
for columns in Query(world, (Position, Velocity))
    @unpack entities, (x, y), (dx, dy) = columns
    @inbounds x .+= dx
    @inbounds y .+= dy
end

# output

```
"""
macro unpack(expr)
    @assert expr.head == :(=) "Expected assignment"
    lhs, rhs = expr.args

    @assert lhs.head == :tuple "Left-hand side must be a tuple"

    n = length(lhs.args)
    rhs_exprs = [:(($rhs)[$i]) for i in 1:n]
    for i in 2:n
        rhs_exprs[i] = :(unpack(($rhs)[$i]))
    end

    new_rhs = Expr(:tuple, rhs_exprs...)
    return Expr(:(=), esc(lhs), esc(new_rhs))
end


"""
    GPUStructArray

A GPU-backed StructArray that stores each component field in a GPUVector.
When passed as a storage the back-end must be specified (either :CUDA, :Metal, 
:oneAPI or :OpenCL).

# Examples

```julia
using CUDA

world = World(
    Position => Storage{GPUStructArray{:CUDA}},
    Velocity => Storage{GPUStructArray{:CUDA}},
)
```
"""
struct GPUStructArray{B,C,CS<:NamedTuple,N} <: _AbstractStructArray{C,CS,N}
    _components::CS
end

function GPUStructArray{B}(tp::Type{C}) where {B,C}
    _GPUStructArray_from_type(tp, Val{B}())
end

@generated function _GPUStructArray_from_type(::Type{C}, ::Val{B}) where {C,B}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("GPUStructArray storage not allowed for components without fields")

    vec_types = [:(GPUVector{$(QuoteNode(B)),$t,gpuvector_type($t, Val{$(QuoteNode(B))}())}) for t in types]
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(vec_types...)}})
    kv_exprs = [
        :($name = GPUVector{$(QuoteNode(B)),$t,gpuvector_type($t, Val{$(QuoteNode(B))}())}()) for (name, t) in zip(names, types)
    ]

    return quote
        GPUStructArray{$(QuoteNode(B)),C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _GPUStructArray_type(::Type{C}, ::Val{B}) where {C,B}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("GPUStructArray storage not allowed for components without fields")

    vec_types = [:(GPUVector{$(QuoteNode(B)),$t,gpuvector_type($t, Val{$(QuoteNode(B))}())}) for t in types]
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(vec_types...)}})

    return quote
        GPUStructArray{$(QuoteNode(B)),C,$nt_type,$num_fields}
    end
end

@generated function _GPUStructArrayView_type(::Type{C}, ::Type{I}, ::Val{B}) where {C,I<:AbstractUnitRange{T},B} where {T<:Integer}
    names = fieldnames(C)
    types = fieldtypes(C)
    vec_types = [:(gpuvector_type($t, Val{$(QuoteNode(B))}())) for t in types]
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(vec_types...)}})
    return quote
        _StructArrayView{C,$nt_type,I}
    end
end

@generated function Base.view(
    sa::GPUStructArray{B,C,CS},
    idx::I,
) where {I<:AbstractUnitRange{<:Integer},B,C,CS<:NamedTuple}
    names = fieldnames(C)
    vec_types = [t.parameters[3] for t in CS.parameters[2].parameters]
    view_exprs = [:($name = view(getfield(sa, :_components).$name.mem, idx)) for name in names]
    nt_type = :(NamedTuple{($(map(QuoteNode, names)...),),Tuple{$(vec_types...)}})
    return quote
        _StructArrayView{C,$nt_type,I}((; $(view_exprs...)), idx)
    end
end

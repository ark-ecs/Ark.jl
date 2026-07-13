
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

function _gpu_backend(::Type{<:GPUStructArray{B}}) where {B}
    return B
end

function GPUStructArray{B}(tp::Type{C}) where {B,C}
    _GPUStructArray_from_type(tp, Val{B}(), Val{_gpuvector_has_hostwrap(Val{B}())}())
end

@generated function _GPUStructArray_from_type(::Type{C}, ::Val{B}, ::Val{H}) where {C,B,H}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("GPUStructArray storage not allowed for components without fields")

    QB = QuoteNode(B)
    vec_types = Expr[:(GPUVector{$QB,$t,_gpuvector_type($t, Val{$QB}()),$H}) for t in types]
    quoted_names = QuoteNode[QuoteNode(name) for name in names]
    nt_type = :(NamedTuple{($(quoted_names...),),Tuple{$(vec_types...)}})
    kv_exprs = Expr[
        :($name = GPUVector{$QB,$t,_gpuvector_type($t, Val{$QB}()),$H}()) for (name, t) in zip(names, types)
    ]

    return quote
        GPUStructArray{$QB,C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _GPUStructArray_type(::Type{C}, ::Val{B}, ::Val{H}) where {C,B,H}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("GPUStructArray storage not allowed for components without fields")

    QB = QuoteNode(B)
    vec_types = Expr[:(GPUVector{$QB,$t,_gpuvector_type($t, Val{$QB}()),$H}) for t in types]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})

    return quote
        GPUStructArray{$QB,C,$nt_type,$num_fields}
    end
end

@generated function _GPUStructArrayView_type(
    ::Type{SA},
    ::Type{I},
) where {SA<:GPUStructArray,I<:AbstractUnitRange{T}} where {T<:Integer}
    B, C, CS, N = SA.parameters
    names = fieldnames(C)
    vec_types = Expr[:(_gpuvectorview_type($vt)) for vt in fieldtypes(CS)]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})
    return quote
        _StructArrayView{$C,$nt_type}
    end
end

@generated function Base.view(
    sa::GPUStructArray{B,C,CS},
    idx::I,
) where {I<:AbstractUnitRange{<:Integer},B,C,CS<:NamedTuple}
    names = fieldnames(C)
    vec_types = Expr[:(_gpuvectorview_type($vt)) for vt in fieldtypes(CS)]
    view_exprs = Expr[:($name = _gpuvector_view(getfield(sa, :_components).$name, idx)) for name in names]
    nt_type = :(NamedTuple{$names,Tuple{$(vec_types...)}})
    return quote
        _StructArrayView{C,$nt_type}((; $(view_exprs...)))
    end
end

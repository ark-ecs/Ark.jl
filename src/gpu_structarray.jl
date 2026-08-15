
"""
    GPUStructArray

A GPU-backed StructArray that stores each component field in a GPUVector.
When passed as a storage the back-end must be specified (either :CUDA, :Metal,
:oneAPI, :OpenCL or :CPU).

As for [`GPUVector`](@ref), the `:CPU` back-end is always available and stores
each field in a plain `Vector`.

As for [`GPUVector`](@ref), the storage can be pinned to a specific device on
back-ends with more than one, by pairing the back-end with a zero-based device
ordinal, like `(:CUDA, 1)` for the second GPU of the system, or by passing a
device object through `Storage(GPUStructArray{:CUDA}, device)`.

# Examples

```julia
using CUDA

world = World(
    Position => Storage{GPUStructArray{:CUDA}},
    Velocity => Storage{GPUStructArray{:CUDA}},
)
```

```julia
using CUDA

world = World(
    Position => Storage{GPUStructArray{(:CUDA, 1)}},
    Velocity => Storage{GPUStructArray{(:CUDA, 1)}},
)
```

```julia
using CUDA

world = World(
    Position => Storage(GPUStructArray{:CUDA}, CuDevice(1)),
    Velocity => Storage(GPUStructArray{:CUDA}, CuDevice(1)),
)
```

```julia
world = World(
    Position => Storage{GPUStructArray{:CPU}},
    Velocity => Storage{GPUStructArray{:CPU}},
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
    _GPUStructArray_from_type(tp, Val{B}())
end

@generated function _GPUStructArray_from_type(::Type{C}, ::Val{B}) where {C,B}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("GPUStructArray storage not allowed for components without fields")

    QB = QuoteNode(B)
    vec_types = Expr[:(GPUVector{$QB,$t,_gpuvector_type($t, Val{$QB}())}) for t in types]
    quoted_names = QuoteNode[QuoteNode(name) for name in names]
    nt_type = :(NamedTuple{($(quoted_names...),),Tuple{$(vec_types...)}})
    kv_exprs = Expr[
        :($name = GPUVector{$QB,$t,_gpuvector_type($t, Val{$QB}())}()) for (name, t) in zip(names, types)
    ]

    return quote
        GPUStructArray{$QB,C,$nt_type,$num_fields}((; $(kv_exprs...)))
    end
end

@generated function _GPUStructArray_type(::Type{C}, ::Val{B}) where {C,B}
    names = fieldnames(C)
    types = fieldtypes(C)
    num_fields = length(types)
    num_fields == 0 && error("GPUStructArray storage not allowed for components without fields")

    QB = QuoteNode(B)
    vec_types = Expr[:(GPUVector{$QB,$t,_gpuvector_type($t, Val{$QB}())}) for t in types]
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
        StructArrayView{$C,$nt_type}
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
        StructArrayView{C,$nt_type}((; $(view_exprs...)))
    end
end

function Storage(::Type{GPUStructArray{B}}, device) where {B}
    _gpuvector_device_check(B)
    return Storage{GPUStructArray{(B, _gpuvector_ordinal(device))}}()
end

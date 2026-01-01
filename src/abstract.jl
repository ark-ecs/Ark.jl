
abstract type _AbstractWorld end

"""
    Relationship

Abstract marker type for relationship components.

# Example

```jldoctest; setup = :(using Ark), output = false
struct ChildOf <: Relationship end

# output

```
"""
abstract type Relationship end

"""
    Storage{T}

Marks component types for using `T` as a [storage](@ref component-storages) in the
world constructor. The default storages supported by `Ark` are `Vector` and `StructArray`.

If, during world construction, the storage mode is not specified, it defaults to `Storage{Vector}`.

In `StructArray` storages, mutable components are not allowed.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
world = World(
    Position,
    Velocity => Storage{StructArray},
)

# output

World(entities=0, comp_types=(Position, Velocity))
```
"""
struct Storage{T<:AbstractVector} end


abstract type _AbstractStructArray{C} <: AbstractArray{C, 1} end


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
world constructor. The default storages supported by `Ark` are `Vector`, [`StructArray`](@ref),
[`GPUSyncVector`](@ref) and [`GPUSyncStructArray`](@ref).

If, during world construction, the storage mode is not specified, it defaults to `Storage{Vector}`.

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

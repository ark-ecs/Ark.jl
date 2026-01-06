
"""
    GPUSyncVector

A hybrid vector implementation that manages data synchronization between a CPU host
vector and a GPU buffer. The implementation is compatible with all major
backends (CUDA.jl, AMDGPU.jl, Metal.jl and oneAPI.jl).

This struct acts as a storage type for components that require computation offloading.
By default, array operations are performed on the CPU. To perform operations on the GPU,
use [`gpuview`](@ref) to obtain a view of the underlying GPU device buffer.

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUSyncVector{CuVector}},
    Velocity => Storage{GPUSyncVector{CuVector}},
)
```
"""
mutable struct GPUSyncVector{T,BT} <: AbstractVector{T}
    const vec::Vector{T}
    buffer::BT
    sync_cpu::Bool
    sync_gpu::Bool
end

function GPUSyncVector{T,BT}() where {T,BT}
    return GPUSyncVector{T,BT}(Vector{T}(), BT(undef, 0), true, true)
end

"""
    gpuview(v::Union{GPUSyncVector, FieldViewable{<:Any, 1, <:GPUSyncVector}}; readonly::Bool=false)

Return a view of the underlying GPU buffer associated with the [`GPUSyncVector`](@ref).

Invoking this function triggers a synchronization: if the GPU buffer is stale, data is
copied from the CPU to the GPU.

# Arguments

  - `v`: The `GPUSyncVector` or a CPU viewable wrapper of it (which is returned by queries).

# Keyword Arguments

  - `readonly::Bool`: If set to `true`, indicates that the returned view will not be written to.

    **Performance Note:** Setting `readonly=true` prevents the vector from marking the GPU data
    as "dirty" (desynchronized). This avoids an unnecessary copy back to the CPU on the next host
    access.

    **Warning:** The caller guarantees that no write operations occur when `readonly=true`.
    Modifying the view when this flag is set results in undefined behavior regarding data
    consistency.

# Examples

```
using CUDA

world = World(
    Position => Storage{GPUSyncVector{CuVector}},
)

new_entities!(world, 100, (Position(0.0, 0.0),))

update(pos) = Position(pos.x + 1.0, pos.y + 1.0) 

for (entities, positions) in Query(world, (Position,))
    pos_gpu = gpuview(positions)
    pos_gpu .= update.(pos_gpu)
end
```
"""
function gpuview(gv::FieldViewable{<:Any,1,<:GPUSyncVector}; readonly::Bool=false)
    return gpuview(parent(gv); readonly=readonly)
end

function gpuview(gv::GPUSyncVector; readonly::Bool=false)
    _resync_gpu!(gv)
    if !readonly
        gv.sync_cpu = false
    end
    return view(gv.buffer, 1:length(gv.vec))
end

function Base.copyto!(gv::GPUSyncVector, doffs::Integer, src::AbstractVector, soffs::Integer, n::Integer)
    _resync_cpu!(gv)
    gv.sync_gpu = false
    copyto!(gv.vec, doffs, src, soffs, n)
    return gv
end

function Base.similar(gv::GPUSyncVector{T,BT}, ::Type{T}, size::Dims{1}) where {T,BT}
    return GPUSyncVector{T,BT}(Vector{T}(undef, size), BT(undef, 0), true, true)
end

Base.eltype(::Type{<:GPUSyncVector{C}}) where {C} = C

function _resync_gpu!(gv::GPUSyncVector{T,BT}) where {T,BT}
    if !gv.sync_gpu
        # TODO: maybe consider shrinking if CPU vector is much smaller
        # to save GPU space
        if length(gv.buffer) < length(gv.vec)
            new_cap = max(length(gv.vec), 2 * length(gv.buffer))
            gv.buffer = BT(undef, new_cap)
        end
        copyto!(gv.buffer, 1, gv.vec, 1, length(gv.vec))
        gv.sync_gpu = true
    end
    return
end

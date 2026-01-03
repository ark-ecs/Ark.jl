
"""
    GPUVector

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
    Position => Storage{GPUVector{CuVector}},
    Velocity => Storage{GPUVector{CuVector}},
)
```
"""
mutable struct GPUVector{T,BT} <: AbstractVector{T}
    const vec::Vector{T}
    buffer::BT
    sync_cpu::Bool
    sync_gpu::Bool
end

function GPUVector{T,BT}() where {T,BT}
    return GPUVector{T,BT}(Vector{T}(), BT(undef,0), true, true)
end

"""
    gpuview(v::Union{GPUVector, FieldViewable{<:Any, 1, <:GPUVector}}; readonly::Bool=false)

Return a view of the underlying GPU buffer associated with the [`GPUVector`](@ref).

Invoking this function triggers a synchronization: if the GPU buffer is stale, data is
copied from the CPU to the GPU.

# Arguments
* `v`: The `GPUVector` or a CPU viewable wrapper of it (which is returned by queries).

# Keyword Arguments
* `readonly::Bool`: If set to `true`, indicates that the returned view will not be written to. 
  
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
    Position => Storage{GPUVector{CuVector}},
)

new_entities!(world, 100, (Position(0.0, 0.0),))

update(pos) = Position(pos.x + 1.0, pos.y + 1.0) 

for (entities, positions) in Query(world, (Position,))
    pos_gpu = gpuview(positions)
    pos_gpu .= update.(pos_gpu)
end
```
"""
function gpuview(s::FieldViewable{<:Any, 1, <:GPUVector}; readonly::Bool=false)
    return gpuview(parent(s); readonly=readonly)
end

function gpuview(s::GPUVector; readonly::Bool=false)
    _resync_gpu!(s)
    if !readonly
        s.sync_cpu = false
    end
    return view(s.buffer, 1:length(s.vec))
end

Base.size(s::GPUVector) = (length(s.vec),)

Base.@propagate_inbounds function Base.getindex(s::GPUVector, i::Int)
    _resync_cpu!(s)
    return s.vec[i]
end

Base.@propagate_inbounds function Base.setindex!(s::GPUVector, v, i::Int)
    _resync_cpu!(s) 
    s.sync_gpu = false 
    s.vec[i] = v
    return v
end

function Base.resize!(s::GPUVector, new_len::Integer)
    _resync_cpu!(s)
    s.sync_gpu = false
    resize!(s.vec, new_len)
    return s
end

function Base.empty!(s::GPUVector)
    s.sync_gpu = false
    empty!(s.vec)
    return s
end

function Base.push!(s::GPUVector, v)
    _resync_cpu!(s)
    s.sync_gpu = false
    push!(s.vec, v)
    return s
end

function Base.pop!(s::GPUVector)
    _resync_cpu!(s) 
    return pop!(s.vec)
end

function Base.sizehint!(s::GPUVector, i::Integer)
    sizehint!(s.vec, i)
    return s
end

Base.IndexStyle(::Type{<:GPUVector}) = IndexLinear()

function _resync_cpu!(s::GPUVector)
    if !s.sync_cpu
        copyto!(s.vec, 1, s.buffer, 1, length(s.vec))
        s.sync_cpu = true
    end
    return
end

function _resync_gpu!(s::GPUVector{T,BT}) where {T,BT}
    if !s.sync_gpu
        if length(s.buffer) < length(s.vec)
            new_cap = max(length(s.vec), 2 * length(s.buffer))
            s.buffer = BT(undef, new_cap)
        end
        copyto!(s.buffer, 1, s.vec, 1, length(s.vec))
        s.sync_gpu = true
    end
    return
end

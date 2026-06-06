"""
    DiskVector

A disk-backed vector implementation for isbits component storage.

`DiskVector` uses a temporary memory-mapped file as backing storage. Files are
managed by Ark and deleted automatically when the vector is garbage-collected.
"""
mutable struct DiskVector{T} <: AbstractVector{T}
    path::String
    io::Union{Nothing,IOStream}
    mem::Vector{T}
    len::Int
    capacity::Int
end

function _check_diskvector_eltype(::Type{T}) where {T}
    if !isbitstype(T)
        throw(ArgumentError("DiskVector storage requires an isbits component type, got $(nameof(T))"))
    elseif sizeof(T) == 0
        throw(ArgumentError("DiskVector storage requires a nonzero-size component type, got $(nameof(T))"))
    end
    return nothing
end

function DiskVector{T}() where {T}
    _check_diskvector_eltype(T)
    dv = DiskVector{T}("", nothing, Vector{T}(), 0, 0)
    finalizer(_finalize_diskvector!, dv)
    return dv
end

function DiskVector{T}(::UndefInitializer, n::Integer) where {T}
    dv = DiskVector{T}()
    resize!(dv, n)
    return dv
end

function _finalize_diskvector!(dv::DiskVector)
    io = dv.io
    mem = dv.mem
    capacity = dv.capacity
    path = dv.path
    @async _cleanup_diskvector_resources!(io, mem, capacity, path)
    return nothing
end

function _cleanup_diskvector_resources!(
    io::Union{Nothing,IOStream},
    mem::Vector,
    capacity::Int,
    path::String,
)
    if io !== nothing
        if capacity > 0
            try
                Mmap.sync!(mem)
            catch
            end
        end
        try
            close(io)
        catch
        end
    end
    if !isempty(path)
        try
            rm(path; force=true)
        catch
        end
    end
    return nothing
end

function _ensure_diskvector_file!(dv::DiskVector)
    if dv.io === nothing
        path, io = mktemp()
        dv.path = path
        dv.io = io
    end
    return dv.io::IOStream
end

function _ensure_diskvector_capacity!(dv::DiskVector{T}, requested::Int) where {T}
    requested <= dv.capacity && return nothing

    io = _ensure_diskvector_file!(dv)
    new_capacity = max(requested, 2 * dv.capacity, 1)

    if dv.capacity > 0
        Mmap.sync!(dv.mem)
    end
    dv.mem = Mmap.mmap(io, Vector{T}, new_capacity, 0; grow=true, shared=true)
    dv.capacity = new_capacity
    return nothing
end

Base.size(dv::DiskVector) = (dv.len,)
Base.length(dv::DiskVector) = dv.len
Base.eltype(::Type{<:DiskVector{T}}) where {T} = T
Base.IndexStyle(::Type{<:DiskVector}) = IndexLinear()

Base.@propagate_inbounds function Base.getindex(dv::DiskVector, i::Int)
    return dv.mem[i]
end

Base.@propagate_inbounds function Base.setindex!(dv::DiskVector, value, i::Int)
    dv.mem[i] = value
    return value
end

function Base.resize!(dv::DiskVector, new_len::Int)
    new_len < 0 && throw(ArgumentError("new length must be ≥ 0"))
    _ensure_diskvector_capacity!(dv, new_len)
    dv.len = new_len
    return dv
end

function Base.sizehint!(dv::DiskVector, capacity::Int)
    capacity > 0 && _ensure_diskvector_capacity!(dv, capacity)
    return dv
end

function Base.empty!(dv::DiskVector)
    dv.len = 0
    return dv
end

function Base.push!(dv::DiskVector, value)
    new_len = dv.len + 1
    _ensure_diskvector_capacity!(dv, new_len)
    @inbounds dv.mem[new_len] = value
    dv.len = new_len
    return dv
end

function Base.pop!(dv::DiskVector)
    dv.len == 0 && throw(ArgumentError("array must be non-empty"))
    value = @inbounds dv.mem[dv.len]
    dv.len -= 1
    return value
end

function Base.fill!(dv::DiskVector, value)
    @inbounds @simd for i in 1:length(dv)
        dv.mem[i] = value
    end
    return dv
end

function Base.copyto!(
    dest::DiskVector,
    doffs::Integer,
    src::DiskVector,
    soffs::Integer,
    n::Integer,
)
    copyto!(dest.mem, doffs, src.mem, soffs, n)
    return dest
end

function Base.unsafe_copyto!(
    dest::DiskVector,
    doffs::Integer,
    src::DiskVector,
    soffs::Integer,
    n::Integer,
)
    unsafe_copyto!(dest.mem, doffs, src.mem, soffs, n)
    return dest
end

function Base.similar(::DiskVector{T}) where {T}
    return DiskVector{T}()
end

function Base.similar(::DiskVector, ::Type{T}, dims::Dims{1}) where {T}
    dv = DiskVector{T}()
    resize!(dv, dims[1])
    return dv
end

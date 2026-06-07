"""
    DiskVector

A disk-backed vector implementation for isbits component storage.

`DiskVector` uses a temporary memory-mapped file as backing storage. Files are
managed by Ark and deleted automatically when the vector is garbage-collected.
"""
const DISKVECTOR_MEMORY_LENGTH = 128

mutable struct DiskVector{T} <: AbstractVector{T}
    path::String
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
    dv = DiskVector{T}("", Vector{T}(), 0, 0)
    finalizer(_finalize_diskvector!, dv)
    return dv
end

function DiskVector{T}(::UndefInitializer, n::Integer) where {T}
    dv = DiskVector{T}()
    resize!(dv, n)
    return dv
end

function _finalize_diskvector!(dv::DiskVector)
    mem = dv.mem
    capacity = dv.capacity
    path = dv.path
    @async _cleanup_diskvector_resources!(mem, capacity, path)
    return nothing
end

function _cleanup_diskvector_resources!(mem::Vector, capacity::Int, path::String)
    if !isempty(path) && capacity > 0
        try
            _release_diskvector_mem!(mem, capacity)
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
    if isempty(dv.path)
        mkpath(TMP_ARK_DIR)
        path, io = mktemp(TMP_ARK_DIR)
        try
            close(io)
        catch
            rm(path; force=true)
            rethrow()
        end
        dv.path = path
    end
    return dv.path
end

function _mmap_diskvector(::Type{T}, path::String, capacity::Int) where {T}
    return open(path, "r+") do io
        Mmap.mmap(io, Vector{T}, capacity, 0; grow=true, shared=true)
    end
end

function _unmap_diskvector_mem!(mem::Vector, capacity::Int)
    capacity == 0 && return nothing
    finalize(mem.ref.mem)
    return nothing
end

function _release_diskvector_mem!(mem::Vector, capacity::Int)
    capacity == 0 && return nothing
    Mmap.sync!(mem)
    _unmap_diskvector_mem!(mem, capacity)
    return nothing
end

function _diskvector_uses_disk(dv::DiskVector, requested::Int)
    return !isempty(dv.path) || requested > DISKVECTOR_MEMORY_LENGTH
end

function _ensure_diskvector_memory_capacity!(dv::DiskVector{T}, requested::Int) where {T}
    requested <= dv.capacity && return nothing

    new_capacity = min(max(requested, 2 * dv.capacity, 1), DISKVECTOR_MEMORY_LENGTH)
    new_mem = Vector{T}(undef, new_capacity)
    if dv.len > 0
        copyto!(new_mem, 1, dv.mem, 1, dv.len)
    end
    dv.mem = new_mem
    dv.capacity = new_capacity
    return nothing
end

function _move_diskvector_to_disk!(dv::DiskVector{T}, requested::Int) where {T}
    old_path = dv.path
    path = _ensure_diskvector_file!(dv)
    new_capacity = max(requested, 2 * dv.capacity, DISKVECTOR_MEMORY_LENGTH + 1)
    old_mem = dv.mem

    try
        new_mem = _mmap_diskvector(T, path, new_capacity)
        if dv.len > 0
            copyto!(new_mem, 1, old_mem, 1, dv.len)
        end
        dv.mem = new_mem
        dv.capacity = new_capacity
    catch
        if isempty(old_path)
            try
                rm(path; force=true)
            catch
            end
            dv.path = ""
        end
        rethrow()
    end
    return nothing
end

function _ensure_diskvector_capacity!(dv::DiskVector{T}, requested::Int) where {T}
    requested <= dv.capacity && return nothing

    if !_diskvector_uses_disk(dv, requested)
        _ensure_diskvector_memory_capacity!(dv, requested)
        return nothing
    elseif isempty(dv.path)
        _move_diskvector_to_disk!(dv, requested)
        return nothing
    end

    path = _ensure_diskvector_file!(dv)
    new_capacity = max(requested, 2 * dv.capacity, 1)

    old_mem = dv.mem
    old_capacity = dv.capacity
    if dv.capacity > 0
        try
            Mmap.sync!(old_mem)
            dv.mem = Vector{T}()
            dv.capacity = 0
            _unmap_diskvector_mem!(old_mem, old_capacity)
        catch
            dv.mem = old_mem
            dv.capacity = old_capacity
            rethrow()
        end
    end

    try
        dv.mem = _mmap_diskvector(T, path, new_capacity)
        dv.capacity = new_capacity
    catch
        if old_capacity > 0
            try
                dv.mem = _mmap_diskvector(T, path, old_capacity)
                dv.capacity = old_capacity
            catch
                dv.mem = Vector{T}()
                dv.capacity = 0
            end
        end
        rethrow()
    end
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
    if capacity > 0 && isempty(dv.path)
        _ensure_diskvector_memory_capacity!(dv, min(capacity, DISKVECTOR_MEMORY_LENGTH))
    end
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

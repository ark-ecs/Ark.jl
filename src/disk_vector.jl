"""
    DiskVector

A disk-backed vector implementation for isbits component storage.

`DiskVector` uses a temporary memory-mapped file as backing storage.

Files are managed by Ark and deleted automatically when the vector is
garbage-collected or at process exit. Files left behind by a process
that crashed are removed by the next Julia session that loads Ark.
"""
mutable struct DiskVector{T} <: AbstractVector{T}
    path::String
    mem::Vector{T}
    len::Int
    capacity::Int
end

const DISKVECTOR_MEMORY_LENGTH = 128

const _ARK_SESSION_DIR = Ref{String}()
const _ARK_SESSION_DIR_LOCK = ReentrantLock()
const _ARK_SESSION_REGEX = r"^ark_session_(\d+)_"

function _ark_session_dir()
    lock(_ARK_SESSION_DIR_LOCK) do
        if !isassigned(_ARK_SESSION_DIR)
            mkpath(TMP_ARK_DIR)
            _ARK_SESSION_DIR[] = mktempdir(TMP_ARK_DIR; prefix="ark_session_$(getpid())_", cleanup=true)
        end
        return _ARK_SESSION_DIR[]
    end
end

function isvalidpid(hostname::AbstractString, pid::Integer)
    (pid <= 0 || pid > typemax(Cuint)) && return false
    pid == getpid() && return true
    return FileWatching.Pidfile.isvalidpid(hostname, Cuint(pid))
end

function _sweep_stale_ark_sessions!()
    isdir(TMP_ARK_DIR) || return nothing
    host = gethostname()
    for entry in readdir(TMP_ARK_DIR)
        m = match(_ARK_SESSION_REGEX, entry)
        if m !== nothing && m.captures !== nothing
            pid = tryparse(Int, m.captures[1])
            if pid !== nothing && isvalidpid(host, pid)
                continue
            end
        end
        try
            rm(joinpath(TMP_ARK_DIR, entry); recursive=true, force=true)
        catch
        end
    end
    return nothing
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
    @async _cleanup_diskvector_resources!(dv.mem, dv.path)
    return nothing
end

function _cleanup_diskvector_resources!(mem::Vector, path::String)
    if !isempty(path)
        try
            finalize(mem)
        catch
        end
        try
            rm(path; force=true)
        catch
        end
    end
    return nothing
end

function _ensure_diskvector_file!(dv::DiskVector)
    if isempty(dv.path)
        path, io = mktemp(_ark_session_dir())
        close(io)
        dv.path = path
    end
    return dv.path
end

function _mmap_diskvector(::Type{T}, path::String, capacity::Int) where {T}
    return open(path, "r+") do io
        Mmap.mmap(io, Vector{T}, capacity, 0; grow=true, shared=true)
    end
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
    new_mem = _mmap_diskvector(T, path, new_capacity)
    if dv.len > 0
        copyto!(new_mem, 1, old_mem, 1, dv.len)
    end
    dv.mem = new_mem
    dv.capacity = new_capacity
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

    old_mem = dv.mem
    old_capacity = dv.capacity
    finalize(old_mem)
    new_capacity = max(requested, 2 * old_capacity, 1)
    dv.mem = _mmap_diskvector(T, dv.path, new_capacity)
    dv.capacity = new_capacity
    return nothing
end

Base.size(dv::DiskVector) = (dv.len,)
Base.length(dv::DiskVector) = dv.len
Base.eltype(::Type{<:DiskVector{T}}) where {T} = T
Base.IndexStyle(::Type{<:DiskVector}) = IndexLinear()

Base.@propagate_inbounds function Base.getindex(dv::DiskVector, i::Int)
    @boundscheck checkbounds(dv, i)
    return @inbounds dv.mem[i]
end

Base.@propagate_inbounds function Base.setindex!(dv::DiskVector, value, i::Int)
    @boundscheck checkbounds(dv, i)
    @inbounds dv.mem[i] = value
    return value
end

function Base.resize!(dv::DiskVector, new_len::Int)
    new_len < 0 && throw(ArgumentError("new length must be ≥ 0"))
    _ensure_diskvector_capacity!(dv, new_len)
    dv.len = new_len
    return dv
end

function Base.sizehint!(dv::DiskVector, capacity::Int)
    if capacity > 0
        _ensure_diskvector_capacity!(dv, capacity)
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

function Base.copyto!(dest::DiskVector, doffs::Integer, src::DiskVector, soffs::Integer, n::Integer)
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

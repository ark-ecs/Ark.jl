
module ArkCUDAInterop

using Ark, CUDA

function Ark._gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
    return CuVector{T,CUDA.UnifiedMemory}
end

Ark._gpu_backend_symbol(::CUDABackend) = :CUDA

function Ark._gpuvector_hostwrap(mem::CuVector{T,CUDA.UnifiedMemory}) where {T}
    return unsafe_wrap(Vector{T}, mem)
end

function Ark._gpuvector_pinned_device(::Val{:CUDA}, ordinal::Integer)
    return CuDevice(ordinal)
end

function Ark._gpuvector_ordinal(dev::CuDevice)
    return CUDA.deviceid(dev)
end

function Ark._gpuvector_withdev(f, dev::CuDevice)
    old = CUDA.device()
    old == dev && return f()
    CUDA.device!(dev)
    try
        return f()
    finally
        CUDA.device!(old)
    end
end

# Equivalent to `cudaconvert(view(mem, rng))`, but built from the raw memory
# pointer without allocating, as FlatQuery stages a view per table and field:
# `view` allocates a derived `CuArray`, and `cudaconvert` its tracking list.
# GPUVector memory is never an offset view; others take the generic path, as
# the unit of `offset` differs between CUDA.jl versions.
function Ark._gpuvector_devview(mem::CuArray{T,1}, rng::AbstractUnitRange) where {T}
    mem.offset == 0 || return CUDA.cudaconvert(view(mem, rng))
    DA = CuDeviceArray{T,1,CUDA.AS.Global}
    offset = (first(rng) - 1) * Base.elsize(DA)
    ptr = reinterpret(Core.LLVMPtr{T,CUDA.AS.Global}, convert(CuPtr{T}, mem.data[].mem) + offset)
    return DA(ptr, (length(rng),), mem.maxsize - offset)
end

# The device count is fixed for the process, and querying it allocates.
const _NDEVICES = Ref(0)

function _ndevices()
    _NDEVICES[] == 0 && (_NDEVICES[] = CUDA.ndevices())
    return _NDEVICES[]
end

# Prefetches like CUDA.jl does for unified memory passed directly to kernels,
# under the same conditions, onto the task's stream so that it precedes kernels
# launched afterwards.
function Ark._gpuvector_prefetch(mem::CuArray{T,1,CUDA.UnifiedMemory}, n::Int) where {T}
    (n == 0 || mem.offset != 0) && return nothing
    _ndevices() == 1 || return nothing
    dev = CUDA.device()
    CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS) == 1 || return nothing
    CUDA.is_capturing() && return nothing
    CUDA.prefetch(mem.data[].mem, n * sizeof(T); device = dev)
    return nothing
end

end

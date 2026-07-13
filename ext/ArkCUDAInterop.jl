
module ArkCUDAInterop

using Ark, CUDA

function Ark._gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
    return CuVector{T,CUDA.UnifiedMemory}
end

# CPU-side accesses go through a zero-copy host Vector aliasing the unified
# memory, which is much faster than scalar indexing of the CuArray. Callers
# must synchronize after GPU kernels before accessing data on the CPU, as the
# host wrapper bypasses CUDA.jl's implicit synchronization. This is only safe
# when the hardware allows the CPU to access managed memory while the GPU is
# active (concurrent managed access, e.g. not on Windows/WDDM or pre-Pascal).
# The check runs once per session, when the first storage is constructed, and
# its result is stored in the `H` type parameter of `GPUVector`.
const _HOSTWRAP_SUPPORTED = Ref(Int8(-1))

function _hostwrap_supported()
    ccall(:jl_generating_output, Cint, ()) == 1 && return false
    CUDA.functional() || return false
    return all(CUDA.devices()) do dev
        CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS) == 1
    end
end

function Ark._gpuvector_has_hostwrap(::Val{:CUDA})
    cached = _HOSTWRAP_SUPPORTED[]
    cached >= 0 && return cached == 1
    supported = _hostwrap_supported()
    _HOSTWRAP_SUPPORTED[] = Int8(supported)
    return supported
end

function Ark._gpuvector_hostwrap(mem::CuVector{T,CUDA.UnifiedMemory}) where {T}
    length(mem) == 0 && return T[]
    return unsafe_wrap(Array, mem)
end

end

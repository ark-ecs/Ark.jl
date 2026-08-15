
module ArkCUDAInterop

using Ark, CUDA

function Ark._gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
    return CuVector{T,CUDA.UnifiedMemory}
end

function Ark._gpuvector_hostwrap(mem::CuVector{T,CUDA.UnifiedMemory}) where {T}
    return unsafe_wrap(Vector{T}, mem)
end

function Ark._gpuvector_pinned_device(::Val{:CUDA}, ordinal::Integer)
    return CuDevice(ordinal)
end

function Ark._gpuvector_ordinal(dev::CuDevice)
    ordinal = CUDA.deviceid(dev)
    0 <= ordinal < length(CUDA.devices()) ||
        throw(ArgumentError("device not found among the CUDA devices"))
    return ordinal
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

end

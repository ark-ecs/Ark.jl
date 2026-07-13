
module ArkCUDAInterop

using Ark, CUDA

function Ark._gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
    return CuVector{T,CUDA.UnifiedMemory}
end

function Ark._gpuvector_has_hostwrap(::Val{:CUDA})
    ccall(:jl_generating_output, Cint, ()) == 1 && return false
    CUDA.functional() || return false
    return all(CUDA.devices()) do dev
        CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS) == 1
    end
end

function Ark._gpuvector_hostwrap(mem::CuVector{T,CUDA.UnifiedMemory}) where {T}
    length(mem) == 0 && return T[]
    return unsafe_wrap(Array, mem)
end

end

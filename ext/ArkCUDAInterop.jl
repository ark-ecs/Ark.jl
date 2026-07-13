
module ArkCUDAInterop

using Ark, CUDA

function Ark._gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
    return CuVector{T,CUDA.UnifiedMemory}
end

function Ark._gpuvector_hostwrap(mem::CuVector{T,CUDA.UnifiedMemory}) where {T}
    return unsafe_wrap(Vector{T}, mem)
end

end

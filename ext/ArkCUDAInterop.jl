
module ArkCUDAInterop

using Ark, CUDA

function Ark._gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
    return CuVector{T,CUDA.UnifiedMemory}
end

end

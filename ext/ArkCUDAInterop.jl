
module ArkCUDAInterop

using Ark, CUDA

function Ark.gpuvector_type(::Type{T}, ::Val{:CUDA}) where T
	return CuVector{T, CUDA.UnifiedMemory}
end

if !hasmethod(CUDA.Adapt.adapt_structure, Tuple{Any, GPUVector})
	CUDA.Adapt.adapt_structure(to, w::GPUVector) = CUDA.Adapt.adapt(to, w.mem)
end

end
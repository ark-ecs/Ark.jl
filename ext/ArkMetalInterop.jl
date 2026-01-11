
module ArkMetalInterop

using Ark, Metal

function Ark.gpuvector_type(::Type{T}, ::Val{:Metal}) where T
    # TODO: verify that this works
    return MtlVector{T,Metal.SharedStorage}
end

if !hasmethod(Metal.Adapt.adapt_structure, Tuple{Any,GPUVector})
    Metal.Adapt.adapt_structure(to, w::GPUVector) = Metal.Adapt.adapt(to, w.mem)
end

end

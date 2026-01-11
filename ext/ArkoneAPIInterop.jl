
module ArkoneAPIInterop

using Ark, oneAPI

function Ark.gpuvector_type(::Type{T}, ::Val{:oneAPI}) where T
    # TODO: verify that this works
    return oneVector{T,oneAPI.oneL0.SharedBuffer}
end

if !hasmethod(oneAPI.Adapt.adapt_structure, Tuple{Any,GPUVector})
    oneAPI.Adapt.adapt_structure(to, w::GPUVector) = oneAPI.Adapt.adapt(to, w.mem)
end

end

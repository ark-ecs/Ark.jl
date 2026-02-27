
module ArkMetalInterop

using Ark, Metal

function Ark._gpuvector_type(::Type{T}, ::Val{:Metal}) where T
    # TODO: verify that this works
    return MtlVector{T,Metal.SharedStorage}
end

end


module ArkoneAPIInterop

using Ark, oneAPI

function Ark._gpuvector_type(::Type{T}, ::Val{:oneAPI}) where T
    # TODO: verify that this works
    return oneVector{T,oneAPI.oneL0.SharedBuffer}
end

end

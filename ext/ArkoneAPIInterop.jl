
module ArkoneAPIInterop

using Ark, oneAPI

function Ark._gpuvector_type(::Type{T}, ::Val{:oneAPI}) where T
    # TODO: verify that this works
    return oneVector{T,oneAPI.oneL0.SharedBuffer}
end

function Ark._gpuvector_has_hostwrap(::Val{:oneAPI})
    return oneAPI.functional()
end

function Ark._gpuvector_hostwrap(mem::oneVector{T,oneAPI.oneL0.SharedBuffer}) where {T}
    length(mem) == 0 && return T[]
    return unsafe_wrap(Array, mem)
end

end


module ArkMetalInterop

using Ark, Metal

function Ark._gpuvector_type(::Type{T}, ::Val{:Metal}) where T
    # TODO: verify that this works
    return MtlVector{T,Metal.SharedStorage}
end

function Ark._gpuvector_hostwrap(mem::MtlVector{T,Metal.SharedStorage}) where {T}
    length(mem) == 0 && return T[]
    return unsafe_wrap(Array, mem)
end

end

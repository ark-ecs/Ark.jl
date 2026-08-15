
module ArkoneAPIInterop

using Ark, oneAPI

function Ark._gpuvector_type(::Type{T}, ::Val{:oneAPI}) where T
    # TODO: verify that this works
    return oneVector{T,oneAPI.oneL0.SharedBuffer}
end

function Ark._gpuvector_hostwrap(mem::oneVector{T,oneAPI.oneL0.SharedBuffer}) where {T}
    return unsafe_wrap(Vector{T}, mem)
end

function Ark._gpuvector_pinned_device(::Val{:oneAPI}, ordinal::Integer)
    return oneAPI.devices()[ordinal+1]
end

function Ark._gpuvector_ordinal(dev::oneAPI.oneL0.ZeDevice)
    idx = findfirst(==(dev), oneAPI.devices())
    idx === nothing && throw(ArgumentError("device not found among the oneAPI devices"))
    return idx - 1
end

function Ark._gpuvector_withdev(f, dev::oneAPI.oneL0.ZeDevice)
    old = oneAPI.device()
    old == dev && return f()
    oneAPI.device!(dev)
    try
        return f()
    finally
        oneAPI.device!(old)
    end
end

end

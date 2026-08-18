
module ArkMetalInterop

using Ark, Metal

function Ark._gpuvector_type(::Type{T}, ::Val{:Metal}) where T
    # TODO: verify that this works
    return MtlVector{T,Metal.SharedStorage}
end

function Ark._gpuvector_hostwrap(mem::MtlVector{T,Metal.SharedStorage}) where {T}
    return unsafe_wrap(Vector{T}, mem)
end

function Ark._gpuvector_pinned_device(::Val{:Metal}, ordinal::Integer)
    return Metal.devices()[ordinal+1]
end

function Ark._gpuvector_ordinal(dev::Metal.MTLDevice)
    idx = findfirst(==(dev), Metal.devices())
    idx === nothing && throw(ArgumentError("device not found among the Metal devices"))
    return idx - 1
end

function Ark._gpuvector_withdev(f, dev::Metal.MTLDevice)
    old = Metal.device()
    old == dev && return f()
    Metal.device!(dev)
    try
        return f()
    finally
        Metal.device!(old)
    end
end

end

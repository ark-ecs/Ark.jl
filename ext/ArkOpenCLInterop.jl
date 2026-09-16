
module ArkOpenCLInterop

using Ark, OpenCL

function Ark._gpuvector_type(::Type{T}, ::Val{:OpenCL}) where T
    memory_backend = cl.unified_memory_backend()
    if memory_backend === cl.USMBackend()
        return CLArray{T,1,cl.UnifiedSharedMemory}
    elseif memory_backend === cl.SVMBackend()
        return CLArray{T,1,cl.SharedVirtualMemory}
    else
        throw(ArgumentError("OpenCL storage not supported since no unified memory back-end was identified"))
    end
end

Ark._gpu_backend_symbol(::OpenCL.OpenCLBackend) = :OpenCL

function Ark._gpuvector_hostwrap(
    mem::CLArray{T,1,<:Union{cl.UnifiedSharedMemory,cl.SharedVirtualMemory}},
) where {T}
    return unsafe_wrap(Vector{T}, mem)
end

function Ark._gpuvector_pinned_device(::Val{:OpenCL}, ordinal::Integer)
    return cl.devices(cl.platform())[ordinal+1]
end

function Ark._gpuvector_ordinal(dev::cl.Device)
    idx = findfirst(==(dev), cl.devices(cl.platform()))
    idx === nothing && throw(ArgumentError("device not found among the OpenCL devices"))
    return idx - 1
end

function Ark._gpuvector_withdev(f, dev::cl.Device)
    return cl.device!(f, dev)
end

function Ark._gpuvector_devview(
    mem::CLArray{<:Any,1,<:Union{cl.UnifiedSharedMemory,cl.SharedVirtualMemory}},
    rng::AbstractUnitRange,
)
    return OpenCL.kernel_convert(view(mem, rng))
end

end


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

function Ark._gpuvector_has_hostwrap(::Val{:OpenCL})
    backend = try
        cl.unified_memory_backend()
    catch
        return false
    end
    return backend === cl.USMBackend() || backend === cl.SVMBackend()
end

function Ark._gpuvector_hostwrap(
    mem::CLArray{T,1,<:Union{cl.UnifiedSharedMemory,cl.SharedVirtualMemory}},
) where {T}
    length(mem) == 0 && return T[]
    return unsafe_wrap(Array, mem)
end

end

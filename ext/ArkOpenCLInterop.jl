
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

end

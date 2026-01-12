
module ArkOpenCLInterop

using Ark, OpenCL

function Ark.gpuvector_type(::Type{T}, ::Val{:OpenCL}) where T
	memory_backend = cl.unified_memory_backend()
    if memory_backend === cl.USMBackend()
        return CLArray{T,1,cl.UnifiedSharedMemory}
    elseif memory_backend === cl.SVMBackend()
        return CLArray{T,1,cl.SharedVirtualMemory}
    else
        throw(ArgumentError("OpenCL storage not supported since no unified memory back-end was identified"))
    end
end

if !hasmethod(OpenCL.Adapt.adapt_structure, Tuple{Any,GPUVector})
    OpenCL.Adapt.adapt_structure(to, w::GPUVector) = OpenCL.Adapt.adapt(to, w.mem)
end

end

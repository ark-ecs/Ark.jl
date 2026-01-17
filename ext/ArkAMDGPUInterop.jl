
module ArkAMDGPUInterop

using Ark, AMDGPU

function Ark._gpuvector_type(::Type{T}, ::Val{:AMDGPU}) where T
    # AMDGPU.jl doesn't support unified memory yet (https://github.com/JuliaGPU/AMDGPU.jl/issues/840)
    # TODO: implement it when unified memory becomes supported
    return throw(error("Not Implemented"))
end

if !hasmethod(AMDGPU.Adapt.adapt_structure, Tuple{Any,GPUVector})
    AMDGPU.Adapt.adapt_structure(to, w::GPUVector) = AMDGPU.Adapt.adapt(to, w.mem)
end

end

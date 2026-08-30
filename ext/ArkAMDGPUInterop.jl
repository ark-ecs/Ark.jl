
module ArkAMDGPUInterop

using Ark, AMDGPU

function Ark._gpu_backend_symbol(::AMDGPU.ROCBackend)
    # AMDGPU.jl doesn't support unified memory yet (https://github.com/JuliaGPU/AMDGPU.jl/issues/840)
    # TODO: implement it when unified memory becomes supported
    return throw(ArgumentError("AMDGPU storage is not supported since AMDGPU.jl lacks unified memory"))
end

end

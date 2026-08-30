
module ArkKernelAbstractionsInterop

using Ark, KernelAbstractions

Ark._gpu_backend_symbol(::KernelAbstractions.CPU) = :CPU

end

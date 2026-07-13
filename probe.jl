using CUDA, BenchmarkTools

dev = CUDA.device()
println("device: ", CUDA.name(dev))
println("driver: ", CUDA.driver_version())
println("pageable access (HMM): ",
    CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_PAGEABLE_MEMORY_ACCESS))
println("pageable uses host PTs: ",
    CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_PAGEABLE_MEMORY_ACCESS_USES_HOST_PAGE_TABLES))
println("concurrent managed access: ",
    CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS))

const N = 1024
v = rand(Float32, N)

# 1) CUDA.jl's unsafe_wrap from a system (CPU) pointer, if HMM is available
hmm = CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_PAGEABLE_MEMORY_ACCESS) == 1
if hmm
    b = @benchmark unsafe_wrap(CuArray{Float32,1,CUDA.UnifiedMemory}, pointer($v), (N,))
    println("\nunsafe_wrap(CuArray{...,UnifiedMemory}, Ptr): ",
        minimum(b.times), " ns, ", b.allocs, " allocs, ", b.memory, " bytes")
end

# 2) unsafe_wrap from a unified CuVector's pointer (CuPtr path, memtype known)
uv = CuVector{Float32,CUDA.UnifiedMemory}(undef, N)
b2 = @benchmark unsafe_wrap(CuArray{Float32,1,CUDA.UnifiedMemory}, pointer($uv), (N,))
println("unsafe_wrap(CuArray{...,UnifiedMemory}, CuPtr): ",
    minimum(b2.times), " ns, ", b2.allocs, " allocs, ", b2.memory, " bytes")

# 3) direct CuDeviceArray construction from a CPU pointer
import CUDA: CuDeviceArray
using Core: LLVMPtr
function make_devarray(v::Vector{Float32})
    p = reinterpret(LLVMPtr{Float32,CUDA.AS.Global}, pointer(v))
    CuDeviceArray{Float32,1,CUDA.AS.Global}(p, (length(v),))
end
b3 = @benchmark make_devarray($v)
println("direct CuDeviceArray from Ptr: ",
    minimum(b3.times), " ns, ", b3.allocs, " allocs, ", b3.memory, " bytes")
println("isbits CuDeviceArray: ", isbits(make_devarray(v)))

# 4) verify a kernel accepts a hand-built CuDeviceArray over HMM system memory
function scale_kernel!(a, s)
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    if i <= length(a)
        @inbounds a[i] *= s
    end
    return
end

if hmm
    v2 = ones(Float32, N)
    da = make_devarray(v2)
    GC.@preserve v2 begin
        CUDA.@sync @cuda threads=256 blocks=cld(N,256) scale_kernel!(da, 2.0f0)
    end
    println("kernel over hand-built CuDeviceArray on system memory: ",
        all(v2 .== 2.0f0) ? "OK" : "WRONG RESULT")

    # launch cost/allocs with pre-compiled kernel
    k = @cuda launch=false scale_kernel!(da, 2.0f0)
    config_threads = 256
    blocks = cld(N, 256)
    b4 = @benchmark GC.@preserve $v2 $k($da, 2.0f0; threads=$config_threads, blocks=$blocks)
    println("pre-compiled kernel launch w/ CuDeviceArray: ",
        minimum(b4.times), " ns, ", b4.allocs, " allocs, ", b4.memory, " bytes")
    CUDA.synchronize()
end

# 5) same kernel launched with a real CuArray argument, for launch-cost comparison
k2 = @cuda launch=false scale_kernel!(CUDA.cudaconvert(uv), 2.0f0)
b5 = @benchmark begin
    da = CUDA.cudaconvert($uv)
    $k2(da, 2.0f0; threads=256, blocks=cld(N,256))
end
println("pre-compiled kernel launch w/ cudaconvert(CuArray): ",
    minimum(b5.times), " ns, ", b5.allocs, " allocs, ", b5.memory, " bytes")
CUDA.synchronize()

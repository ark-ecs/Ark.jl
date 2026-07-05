
include("main.jl")

main(CPU())

# For better performance, use a GPU backend like so:
#
# using CUDA
# main(CUDABackend())

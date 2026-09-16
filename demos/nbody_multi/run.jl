include("main.jl")

if VERIFY_ONLY
    verify_nbody_multi(CPU())

    # For better performance, use a GPU backend like so:
    #
    # using CUDA
    # verify_nbody_multi(CUDABackend())
else
    main(CPU())

    # For better performance, use a GPU backend like so:
    #
    # using CUDA
    # main(CUDABackend())
end

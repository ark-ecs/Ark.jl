include("main.jl")

if VERIFY_ONLY
    # Verification reads components on the host, so it runs on the CPU back-end.
    verify_nbody_multi(CPU())
else
    #main(CPU())

    # For better performance, use a GPU backend like so:
    #
    using CUDA
    main(CUDABackend())
end

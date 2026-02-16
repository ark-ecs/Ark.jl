
@testset "_Lock basic functionality" begin
    lock = _Lock()

    # Initially, nothing should be locked
    @test !_is_locked(lock)
    @test lock._counter == 0

    # Lock one time
    _lock(lock)
    @test _is_locked(lock)
    @test lock._counter == 1

    # Unlock one time
    _unlock(lock)
    @test lock._counter == 0
    @test !_is_locked(lock)

    for _ in 1:2
        Threads.@sync begin
            Threads.@spawn for _ in 1:10^3
                _lock(lock)
            end
            Threads.@spawn for _ in 1:10^3
                _unlock(lock)
            end
        end
    end

    @test lock._counter == 0
    @test !_is_locked(lock)
end

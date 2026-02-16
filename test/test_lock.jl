
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

    Threads.@sync begin
        for _ in 1:10^5
            Threads.@spawn _lock(lock)
            Threads.@spawn _unlock(lock)
        end
    end

    @test lock._counter == 0
    @test !_is_locked(lock)
end

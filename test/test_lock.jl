
@testset "_Lock basic functionality" begin
    lock = _Lock()

    # Initially, nothing should be locked
    @test !_is_locked(lock)
    @test lock._lock_counter.counter == 0

    # Lock one time
    _lock(lock)
    @test _is_locked(lock)
    @test lock._lock_counter.counter == 1

    # Unlock one time
    _unlock(lock)
    @test lock._lock_counter.counter == 0
    @test !_is_locked(lock)
end

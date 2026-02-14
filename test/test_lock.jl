
@testset "_Lock functionality" begin
    lock = _Lock()

    # Initially, nothing should be locked
    @test !_is_locked(lock)
    @test lock.lock_counter == 0

    # Lock one time
    _lock(lock)
    @test _is_locked(lock)
    @test lock.lock_counter == 1

    # Unlock one time
    _unlock(lock)
    @test lock.lock_counter == 0
    @test !_is_locked(lock)
end

using Ark: _Lock, _lock, _unlock

function setup_lock_unlock(n::Int)
    lock = _Lock()
    l = _lock(lock)
    _unlock(lock)

    return lock
end

function benchmark_lock_unlock(args, n)
    lock = args
    for i in 1:n
        _lock(lock)
        _unlock(lock)
    end
    return lock
end

SUITE["benchmark_lock_unlock n=1000"] =
    @be setup_lock_unlock(1000) benchmark_lock_unlock(_, 1000) seconds = SECONDS

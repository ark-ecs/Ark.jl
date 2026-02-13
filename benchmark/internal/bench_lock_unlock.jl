using Ark: _Lock, _lock, _unlock, _lock_safe, _unlock_safe

function setup_lock_unlock(n::Int)
    lock = _Lock()
    l = _lock(lock)
    _unlock(lock, l)

    return lock
end

function benchmark_lock_unlock(args, n)
    lock = args
    for i in 1:n
        l = _lock(lock)
        _unlock(lock, l)
    end
    return lock
end

SUITE["benchmark_lock_unlock n=1000"] =
    @be setup_lock_unlock(1000) benchmark_lock_unlock(_, 1000) seconds = SECONDS

function setup_lock_unlock_safe(n::Int)
    lock = _Lock()
    l = _lock_safe(lock)
    _unlock_safe(lock, l)

    return lock
end

function benchmark_lock_unlock_safe(args, n)
    lock = args
    for i in 1:n
        l = _lock_safe(lock)
        _unlock_safe(lock, l)
    end
    return lock
end

SUITE["benchmark_lock_unlock_safe n=1000"] =
    @be setup_lock_unlock_safe(1000) benchmark_lock_unlock_safe(_, 1000) seconds = SECONDS

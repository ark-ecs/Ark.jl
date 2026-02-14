
struct _Lock
    lock_counter::Threads.Atomic{Int}
end

function _Lock()
    _Lock(Threads.Atomic{Int}(0))
end

function _lock(lock::_Lock)::Int
    @check lock.lock_counter[] >= 0
    Threads.atomic_add!(lock.lock_counter, 1)
end

function _unlock(lock::_Lock)
    @check lock.lock_counter[] > 0
    Threads.atomic_sub!(lock.lock_counter, 1)
end

function _is_locked(lock::_Lock)::Bool
    @check lock.lock_counter[] >= 0
    return lock.lock_counter[] != 0
end

function _reset!(lock::_Lock)
    return
end

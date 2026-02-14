
mutable struct _Counter
    @atomic counter::Int
end

struct _Lock
    _lock_counter::_Counter
end

function _Lock()
    _Lock(_Counter(0))
end

function _lock(lock::_Lock)::Int
    counter = lock._lock_counter
    @check (@atomic :monotonic counter.counter) >= 0
    @atomic :monotonic counter.counter += 1
end

function _unlock(lock::_Lock)
    counter = lock._lock_counter
    @check (@atomic :monotonic counter.counter) > 0
    @atomic :monotonic counter.counter -= 1
end

function _is_locked(lock::_Lock)::Bool
    counter = lock._lock_counter
    @check (@atomic :monotonic counter.counter) >= 0
    return (@atomic :monotonic counter.counter) != 0
end

function _reset!(lock::_Lock)
    return
end

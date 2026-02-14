
mutable struct _Lock
    @atomic lock_counter::Int
end

function _Lock()
    _Lock(0)
end

function _lock(lock::_Lock)::Int
    @check lock.lock_counter >= 0
    @atomic :monotonic lock.lock_counter += 1
    return
end

function _unlock(lock::_Lock)
    @check lock.lock_counter[] > 0
    @atomic :monotonic lock.lock_counter -= 1
end

function _is_locked(lock::_Lock)::Bool
    @check lock.lock_counter >= 0
    return (@atomic :monotonic lock.lock_counter) != 0
end

function _reset!(lock::_Lock)
    return
end

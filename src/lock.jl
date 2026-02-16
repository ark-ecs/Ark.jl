
macro maybe_atomic(expr)
    return THREAD_SAFE_LOCK == "true" ? :(@atomic :monotonic $expr) : (:($expr))
end

mutable struct _Lock
    @maybe_atomic _counter::Int
end

function _Lock()
    _Lock(0)
end

function _lock(lock::_Lock)::Int
    @check (@maybe_atomic lock._counter) >= 0
    @maybe_atomic lock._counter += 1
end

function _unlock(lock::_Lock)
    @check (@maybe_atomic lock._counter) > 0
    @maybe_atomic lock._counter -= 1
end

function _is_locked(lock::_Lock)::Bool
    @check (@maybe_atomic lock._counter) >= 0
    return (@maybe_atomic lock._counter) != 0
end

function _reset!(lock::_Lock)
    return
end

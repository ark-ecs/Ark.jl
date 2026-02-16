
macro _maybe_atomic_f(expr)
    return THREAD_SAFE_LOCK == "true" ? esc(:(@atomic $expr)) : esc(:($expr))
end

macro _maybe_atomic(expr)
    return THREAD_SAFE_LOCK == "true" ? esc(:(@atomic :monotonic $expr)) : esc(:($expr))
end

mutable struct _Lock
    @_maybe_atomic_f _counter::Int
end

function _Lock()
    _Lock(0)
end

function _lock(lock::_Lock)::Int
    @check (@_maybe_atomic lock._counter) >= 0
    @_maybe_atomic lock._counter += 1
end

function _unlock(lock::_Lock)
    @check (@_maybe_atomic lock._counter) > 0
    @_maybe_atomic lock._counter -= 1
end

function _is_locked(lock::_Lock)::Bool
    @check (@_maybe_atomic lock._counter) >= 0
    return (@_maybe_atomic lock._counter) != 0
end

function _reset!(lock::_Lock)
    return
end

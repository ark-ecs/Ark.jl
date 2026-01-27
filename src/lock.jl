mutable struct _Lock
    const pool::_BitPool
    lock_bits::UInt64
    thread_lock::ReentrantLock
end

function _Lock()
    _Lock(_BitPool(), 0, ReentrantLock())
end

function _lock(lock::_Lock)::Int
    l = _get_bit(lock.pool)
    lock.lock_bits |= UInt64(1) << ((l - 1) % UInt64)
    return l
end

function _lock_safe(lo::_Lock)::Int
    l = 0
    lock(lo.thread_lock)
    l = _lock(lo)
    unlock(lo.thread_lock)
    return l
end

function _unlock(lock::_Lock, b::Int)
    if !(((lock.lock_bits >> ((b - 1) % UInt64)) & UInt64(1)) % Bool)
        throw(
            InvalidStateException(
                "unbalanced unlock. Did you close a query that was already iterated?",
                :unbalanced_lock,
            ),
        )
    end
    lock.lock_bits &= ~(UInt64(1) << ((b - 1) % UInt64))
    _recycle(lock.pool, b)
end

function _unlock_safe(lo::_Lock, b::Int)
    lock(lo.thread_lock)
    if ((lo.lock_bits >> (b - 1)) & 0x01) == 0
        unlock(lo.thread_lock)
        throw(
            InvalidStateException(
                "unbalanced unlock. Did you close a query that was already iterated?",
                :unbalanced_lock,
            ),
        )
    end
    lo.lock_bits &= ~(UInt64(1) << (b - 1))
    _recycle(lo.pool, b)
    unlock(lo.thread_lock)
end

function _is_locked(lock::_Lock)::Bool
    return lock.lock_bits != 0
end

function _reset!(lock::_Lock)
    _reset!(lock.pool)
end

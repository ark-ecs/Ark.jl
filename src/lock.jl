mutable struct _Lock
    @atomic _counter::Int
end

function _Lock()
    _Lock(0)
end

function _lock(lock::_Lock)::Int
    #@check (@atomic :monotonic lock._counter) >= 0
    @atomic :monotonic lock._counter += 1
end

function _unlock(lock::_Lock)
    #@check (@atomic :monotonic lock._counter) > 0
    @atomic :monotonic lock._counter -= 1
end

function _is_locked(lock::_Lock)::Bool
    #@check (@atomic :monotonic lock._counter) >= 0
    return (@atomic :monotonic lock._counter) != 0
end

function _reset!(lock::_Lock)
    return
end

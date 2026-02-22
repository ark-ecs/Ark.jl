mutable struct _EntityPool
    entities::Memory{Entity}
    len::Int
    next::Int
end

function _EntityPool(cap::UInt32)
    mem_cap = max(2, Int(cap))
    mem = Memory{Entity}(undef, mem_cap)
    
    @inbounds mem[1] = _new_entity(UInt32(0), typemax(UInt32))
    
    return _EntityPool(mem, 1, 0)
end

@inline function _get_entity(p::_EntityPool)::Entity
    if p.next == 0
        return _get_new_entity(p)
    end
    
    curr = p.next
    @inbounds temp = p.entities[curr]

    p.next = temp._id
    
    entity = _Entity(curr % UInt32, temp._gen) 
    @inbounds p.entities[curr] = entity

    return entity
end

@inline function _get_new_entity(p::_EntityPool)::Entity
    len = p.len + 1
    
    if len > length(p.entities)
        old_cap = length(p.entities)

        new_cap = clamp(overallocation(old_cap), old_cap+1, typemax(UInt32))

        new_mem = Memory{Entity}(undef, new_cap)
        unsafe_copyto!(new_mem, 1, p.entities, 1, p.len)
        p.entities = new_mem
    end
    
    p.len = len
    e = _new_entity(len % UInt32, UInt32(0))
    @inbounds p.entities[len] = e
    
    return e
end

@inline function _recycle(p::_EntityPool, e::Entity)
    if e._id < 2
        throw(ArgumentError("can't recycle the reserved zero entity"))
    end
    
    temp = p.next
    p.next = e._id
    
    @inbounds p.entities[e._id] = _new_entity(temp % UInt32, e._gen + UInt32(1))
    
    return nothing
end

function _is_alive(p::_EntityPool, e::Entity)::Bool
    @inbounds return e._gen == p.entities[e._id]._gen
end

function _reset!(p::_EntityPool)
    p.len = 1
    p.next = 0
    return nothing
end

# Copied from base/array.jl because this is not a public function
# https://github.com/JuliaLang/julia/blob/v1.11.6/base/array.jl#L1042-L1056
function overallocation(maxsize)
    maxsize < 8 && return 8;
    # compute maxsize = maxsize + 4*maxsize^(7/8) + maxsize/8
    # for small n, we grow faster than O(n)
    # for large n, we grow at O(n/8)
    # and as we reach O(memory) for memory>>1MB,
    # this means we end by adding about 10% of memory each time
    exp2 = sizeof(maxsize) * 8 - Core.Intrinsics.ctlz_int(maxsize)
    maxsize += (1 << div(exp2 * 7, 8)) * 4 + div(maxsize, 8)
    return maxsize
end

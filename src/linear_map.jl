
const _LOAD_FACTOR = 0.75
const _RSHIFT = 8 * sizeof(UInt) - 8

struct NoZero end

mutable struct _Linear_Map{K,V,ZK,ZV,ZKT,ZVT}
    keys::Memory{K}
    vals::Memory{V}
    occupied::Memory{UInt8}
    count::Int
    mask::Int
    max_load::Int
    const zero_key::ZKT
    const zero_value::ZVT
    function _Linear_Map{K,V}(
        initial_size::Int=2; zero_key=NoZero(), zero_value=NoZero(),
    ) where {K,V}
        @assert zero_key isa NoZero || zero_key isa K
        @assert zero_value isa NoZero || zero_value isa V
        # Force power of 2 size
        sz = nextpow(2, initial_size)
        keys = Memory{K}(undef, sz)
        vals = Memory{V}(undef, sz)
        occupied = Memory{UInt8}(undef, sz)
        fill!(occupied, 0x00)
        max_load = floor(Int, sz * _LOAD_FACTOR)
        ZK = isbitstype(K) || (zero_key isa NoZero)
        ZV = isbitstype(V) || (zero_value isa NoZero)
        ZKT = typeof(zero_key)
        ZVT = typeof(zero_value)
        new{K,V,ZK,ZV,ZKT,ZVT}(keys, vals, occupied, 0, sz - 1, max_load, zero_key, zero_value)
    end
end

function _grow!(d::_Linear_Map{K,V}) where {K,V}
    old_keys = d.keys
    old_vals = d.vals
    old_occupied = d.occupied
    old_cap = length(old_keys)

    new_cap = old_cap << 1
    new_mask = new_cap - 1
    new_keys = Memory{K}(undef, new_cap)
    new_vals = Memory{V}(undef, new_cap)
    new_occupied = Memory{UInt8}(undef, sz)
    fill!(new_occupied, 0x00)

    @inbounds for i in 1:old_cap
        h2 = old_occupied[i]
        if h2 != 0x00
            k = old_keys[i]
            v = old_vals[i]
            idx = (hash(k) & new_mask) % Int + 1
            while new_occupied[idx] != 0x00
                idx = (idx & new_mask) + 1
            end
            new_keys[idx] = k
            new_vals[idx] = v
            new_occupied[idx] = h2
        end
    end

    d.keys = new_keys
    d.vals = new_vals
    d.occupied = new_occupied
    d.mask = new_mask
    d.max_load = floor(Int, new_cap * _LOAD_FACTOR)
end

function _get_zero_index_loop(d, h)
    mask = d.mask
    idx = (h & mask) % Int + 1
    @inbounds while d.occupied[idx] != 0x00
        idx = (idx & mask) + 1
    end
    return idx
end

macro _get_value_loop(return_val)
    return esc(quote
        mask = d.mask
        h = hash(key)
        idx = (h & mask) % Int + 1
        h2 = (h >> _RSHIFT) % UInt8 | 0x01
        @inbounds h2_idx = d.occupied[idx]
        @inbounds while h2_idx != 0x00
            if h2 == h2_idx && isequal(d.keys[idx], key)
                return $return_val
            end
            idx = (idx & mask) + 1
            h2_idx = d.occupied[idx]
        end
    end)
end

macro _set_new_key()
    return esc(quote
        if d.count >= d.max_load
            _grow!(d)
            idx = _get_zero_index_loop(d, h)
        end
        @inbounds begin
            d.keys[idx] = key
            d.vals[idx] = val
            d.occupied[idx] = h2
            d.count += 1
        end
        return val
    end)
end

macro _remove_key(return_val)
    return esc(quote
        mask = d.mask
        h = hash(key)
        idx = (h & mask) % Int + 1
        h2 = (h >> _RSHIFT) % UInt8 | 0x01
        @inbounds h2_idx = d.occupied[idx]
        @inbounds while h2_idx != 0x00
            if h2_idx == h2 && isequal(d.keys[idx], key)
                old_val = $return_val
                _backshift_delete!(d, idx)
                d.count -= 1
                return old_val
            end
            idx = (idx & mask) + 1
            h2_idx = d.occupied[idx]
        end
    end)
end

put_zero_keys!(d::_Linear_Map{K,V,true}) where {K,V} = nothing
function put_zero_keys!(d::_Linear_Map{K,V,false}) where {K,V}
    for i in eachindex(d.keys)
        d.keys[i] = d.zero_key
    end
end

put_zero_vals!(d::_Linear_Map{K,V,ZK,true}) where {K,V,ZK} = nothing
function put_zero_vals!(d::_Linear_Map{K,V,ZK,false}) where {K,V,ZK}
    for i in eachindex(d.vals)
        d.vals[i] = d.zero_value
    end
end

function Base.empty!(d::_Linear_Map)
    d.count = 0
    d.occupied .= 0x00
    put_zero_keys!(d)
    put_zero_vals!(d)
    return d
end

function Base.haskey(d::_Linear_Map, key)
    @_get_value_loop(true)
    return false
end

function Base.getindex(d::_Linear_Map, key)
    @_get_value_loop(d.vals[idx])
    throw(KeyError(key))
end

function Base.get(f::Union{Function,Type}, d::_Linear_Map, key)
    @_get_value_loop(d.vals[idx])
    return f()
end

function Base.get(d::_Linear_Map, key, default)
    @_get_value_loop(d.vals[idx])
    return default
end

function Base.get!(f::Union{Function,Type}, d::_Linear_Map, key)
    @_get_value_loop(d.vals[idx])
    val = f()
    @_set_new_key()
end

function Base.setindex!(d::_Linear_Map, val, key)
    @_get_value_loop(d.vals[idx] = val)
    @_set_new_key()
end

function _backshift_delete!(d::_Linear_Map, hole::Int)
    mask = d.mask
    next = (hole & mask) + 1

    @inbounds while d.occupied[next] != 0x00
        start = (hash(d.keys[next]) & mask) % Int + 1
        # move next into hole iff hole lies on this key probe path
        if ((next - start) & mask) > ((hole - start) & mask)
            d.keys[hole] = d.keys[next]
            d.vals[hole] = d.vals[next]
            d.occupied[hole] = d.occupied[next]
            hole = next
        end
        next = (next & mask) + 1
    end

    @inbounds d.occupied[hole] = 0x00
    put_zero_key!(d, hole)
    put_zero_val!(d, hole)
    return nothing
end

put_zero_key!(d::_Linear_Map{K,V,true}, idx) where {K,V} = nothing
function put_zero_key!(d::_Linear_Map{K,V,false}, idx) where {K,V}
    @inbounds d.keys[idx] = d.zero_key
end

put_zero_val!(d::_Linear_Map{K,V,ZK,true}, idx) where {K,V,ZK} = nothing
function put_zero_val!(d::_Linear_Map{K,V,ZK,false}, idx) where {K,V,ZK}
    @inbounds d.vals[idx] = d.zero_value
end

function Base.delete!(d::_Linear_Map, key)
    @_remove_key(d)
    return d
end

function Base.pop!(d::_Linear_Map, key)
    @_remove_key(d.vals[idx])
    throw(KeyError(key))
end

struct _Linear_Map_Keys{K,V}
    d::_Linear_Map{K,V}
end

struct _Linear_Map_Values{K,V}
    d::_Linear_Map{K,V}
end

Base.keys(d::_Linear_Map{K,V}) where {K,V} = _Linear_Map_Keys(d)
Base.values(d::_Linear_Map{K,V}) where {K,V} = _Linear_Map_Values(d)

macro _iterate_loop(return_val)
    return esc(quote
        @inbounds while i <= length(d.occupied)
            if d.occupied[i] != 0x00
                return ($return_val, i + 1)
            else
                i += 1
            end
        end
        return nothing
    end)
end

function Base.iterate(d::_Linear_Map{K,V}, i::Int=1) where {K,V}
    @_iterate_loop(d.keys[i] => d.vals[i])
end

function Base.iterate(it::_Linear_Map_Keys{K,V}, i::Int=1) where {K,V}
    d = it.d
    @_iterate_loop(d.keys[i])
end

function Base.iterate(it::_Linear_Map_Values{K,V}, i::Int=1) where {K,V}
    d = it.d
    @_iterate_loop(d.vals[i])
end

Base.length(d::_Linear_Map) = d.count
Base.length(it::_Linear_Map_Keys) = length(it.d)
Base.length(it::_Linear_Map_Values) = length(it.d)

Base.IteratorSize(::Type{<:_Linear_Map}) = Base.HasLength()
Base.IteratorSize(::Type{<:_Linear_Map_Keys}) = Base.HasLength()
Base.IteratorSize(::Type{<:_Linear_Map_Values}) = Base.HasLength()

Base.eltype(::Type{<:_Linear_Map{K,V}}) where {K,V} = Pair{K,V}
Base.eltype(::Type{<:_Linear_Map_Keys{K,V}}) where {K,V} = K
Base.eltype(::Type{<:_Linear_Map_Values{K,V}}) where {K,V} = V


struct _Not end

abstract type _AbstractMask{M} end

struct _Mask{M} <: _AbstractMask{M}
    bits::NTuple{M,UInt64}
end

function _Mask{M}() where M
    return _Mask(ntuple(_ -> UInt64(0), M))
end

function _Mask{1}(bits::Integer...)
    chunk = UInt64(0)
    for b in bits
        @check 1 ≤ b ≤ 64
        offset = (b - 1) % UInt64
        chunk |= (UInt64(1) << offset)
    end
    return _Mask((chunk,))
end

function _Mask{M}(bits::T...) where {M,T<:Integer}
    chunks = ntuple(_ -> UInt64(0), M)
    for b in bits
        @check 1 ≤ b ≤ M * 64
        chunk = (b - 1) >>> 6
        offset = ((b - 1) & T(0x3F)) % UInt64
        chunks = Base.setindex(chunks, chunks[chunk+1] | (UInt64(1) << offset), chunk + 1)
    end
    return _Mask(chunks)
end

function _Mask{M}(::_Not) where M
    return _Mask(ntuple(_ -> typemax(UInt64), M))
end

function _Mask{1}(::_Not, bits::Integer...)
    chunk = typemax(UInt64)
    for b in bits
        @check 1 ≤ b ≤ 64
        offset = (b - 1) % UInt64
        chunk &= ~(UInt64(1) << offset)
    end
    return _Mask((chunk,))
end

function _Mask{M}(::_Not, bits::T...) where {M,T<:Integer}
    chunks = ntuple(_ -> typemax(UInt64), M)  # 0xFFFFFFFFFFFFFFFF
    for b in bits
        @check 1 ≤ b ≤ M * 64
        chunk = (b - 1) >>> 6
        offset = ((b - 1) & T(0x3F)) % UInt64
        mask = ~(UInt64(1) << offset)
        chunks = Base.setindex(chunks, chunks[chunk+1] & mask, chunk + 1)
    end
    return _Mask(chunks)
end

@generated function _contains_all(mask1::_Mask{M}, mask2::_Mask{M})::Bool where M
    expr = Expr[]
    for i in 1:M
        push!(expr, :(((mask1.bits[$i] & mask2.bits[$i]) == mask2.bits[$i])))
    end
    return Expr(:call, :*, expr...)
end

@generated function _contains_any(mask1::_Mask{M}, mask2::_Mask{M})::Bool where M
    expr = Expr[]
    for i in 1:M
        push!(expr, :(((mask1.bits[$i] & mask2.bits[$i]) == 0)))
    end
    expr_call = Expr(:call, :*, expr...)
    return :(!(($expr_call)))
end

@generated function _and(a::_Mask{M}, b::_Mask{M})::_Mask{M} where M
    expr = Expr[]
    for i in 1:M
        push!(expr, :(a.bits[$i] & b.bits[$i]))
    end
    return :(_Mask{$M}(($(expr...),)))
end

@generated function _or(a::_Mask{M}, b::_Mask{M})::_Mask{M} where M
    expr = Expr[]
    for i in 1:M
        push!(expr, :(a.bits[$i] | b.bits[$i]))
    end
    return :(_Mask{$M}(($(expr...),)))
end

@inline @generated function _clear_bits(a::_Mask{M}, b::_Mask{M})::_Mask{M} where M
    expr = Expr[]
    for i in 1:M
        push!(expr, :(a.bits[$i] & ~b.bits[$i]))
    end
    return :(_Mask{$M}(($(expr...),)))
end

@inline function _is_zero(m::_Mask{M})::Bool where M
    return m == _Mask{M}()
end

_is_not_zero(m::_Mask)::Bool = !_is_zero(m)

function _active_bit_indices(mask::_Mask{M})::Vector{Int} where M
    indices = Int[]
    for chunk_index in 1:M
        chunk = mask.bits[chunk_index]
        base = (chunk_index - 1) * 64
        while chunk != 0
            tz = trailing_zeros(chunk)
            push!(indices, base + tz + 1)
            chunk &= chunk - UInt64(1) # clear lowest set bit
        end
    end
    return indices
end

# TODO: simplify this when Julia 1.13 is released
# from new hashing methodology in Base on Julia nightly
const tuplehash_seed = UInt === UInt64 ? 0x77cfa1eef01bca90 : 0xf01bca90
hash_mix_linear(x::Union{UInt64,UInt32}, h::UInt) = 3h - x
function hash_finalizer(x::UInt64)
    x ⊻= (x >> 32)
    x *= 0x63652a4cd374b267
    x ⊻= (x >> 33)
    return x
end
_hash(x::UInt64, h::UInt) = hash_finalizer(hash_mix_linear(x, h))
_hash(::Tuple{}, h::UInt) = h ⊻ tuplehash_seed
_hash(t::Tuple, h::UInt) = _hash(t[1], _hash(Base.tail(t), h))
Base.hash(m::_Mask, h::UInt) = _hash(m.bits[1], _hash(Base.tail(m.bits), h))

mutable struct _MutableMask{M} <: _AbstractMask{M}
    bits::NTuple{M,UInt64}
end

@inline _zero_bits(::Val{M}) where {M} =
    ntuple(_ -> UInt64(0), Val(M))

function _MutableMask{M}() where {M}
    return _MutableMask{M}(_zero_bits(Val(M)))
end

function _MutableMask(mask::_Mask{M}) where {M}
    return _MutableMask{M}(mask.bits)
end

@generated function _replace_chunk(bits::NTuple{M,UInt64}, k::Int, x::UInt64)::NTuple{M,UInt64} where {M}
    exprs = Expr[]
    for j in 1:M
        push!(exprs, :(ifelse(k == $j, x, bits[$j])))
    end
    return Expr(:tuple, exprs...)
end

@generated function _contains_all(mask1::_MutableMask{M}, mask2::_Mask{M})::Bool where {M}
    exprs = Expr[]
    for i in 1:M
        push!(exprs, :(((mask1.bits[$i] & mask2.bits[$i]) == mask2.bits[$i])))
    end
    return Expr(:call, :&, exprs...)
end

@generated function _contains_any(mask1::_Mask{M}, mask2::_MutableMask{M})::Bool where {M}
    exprs = Expr[]
    for i in 1:M
        push!(exprs, :(((mask1.bits[$i] & mask2.bits[$i]) != 0)))
    end
    return Expr(:call, :|, exprs...)
end

function _set_mask!(mask::_MutableMask{M}, other::_Mask{M}) where {M}
    mask.bits = other.bits
    return mask
end

function _clear_mask!(mask::_MutableMask{M}) where {M}
    mask.bits = _zero_bits(Val(M))
    return mask
end

@generated function _equals(mask1::_MutableMask{M}, mask2::_Mask{M})::Bool where {M}
    exprs = Expr[]
    for i in 1:M
        push!(exprs, :((mask1.bits[$i] == mask2.bits[$i])))
    end
    return Expr(:call, :&, exprs...)
end

function _Mask(mask::_MutableMask{M}) where {M}
    return _Mask{M}(mask.bits)
end

@inline function _set_bit!(mask::_MutableMask{1}, i::Int)
    offset = (i - 1) & 63
    val = UInt64(1) << offset
    mask.bits = (mask.bits[1] | val,)
    return mask
end

@inline function _set_bit!(mask::_MutableMask{M}, i::Int) where {M}
    chunk = ((i - 1) >>> 6) + 1
    offset = (i - 1) & 63
    val = UInt64(1) << offset
    bits = mask.bits
    mask.bits = _replace_chunk(bits, chunk, bits[chunk] | val)
    return mask
end

@inline function _clear_bit!(mask::_MutableMask{1}, i::Int)
    offset = (i - 1) & 63
    val = ~(UInt64(1) << offset)
    mask.bits = (mask.bits[1] & val,)
    return mask
end

@inline function _clear_bit!(mask::_MutableMask{M}, i::Int) where {M}
    chunk = ((i - 1) >>> 6) + 1
    offset = (i - 1) & 63
    val = ~(UInt64(1) << offset)
    bits = mask.bits
    mask.bits = _replace_chunk(bits, chunk, bits[chunk] & val)
    return mask
end

@inline function _get_bit(mask::Union{_Mask{1},_MutableMask{1}}, i::Int)::Bool
    offset = (i - 1) & 63
    return ((mask.bits[1] >> offset) & UInt64(1)) == UInt64(1)
end

@inline function _get_bit(mask::Union{_Mask{M},_MutableMask{M}}, i::Int)::Bool where {M}
    chunk = ((i - 1) >>> 6) + 1
    offset = (i - 1) & 63
    return ((mask.bits[chunk] >> offset) & UInt64(1)) == UInt64(1)
end

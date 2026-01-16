
mutable struct TestVector{T} <: AbstractVector{T}
    v::Vector{T}
    inds::UnitRange{Int}
end
TestVector{T}(v::Vector) where {T} = TestVector{T}(v, 1:length(v))
TestVector{T}() where {T} = TestVector{T}(Vector{T}())
function TestVector{T}(::UndefInitializer, i::Integer) where T
    TestVector{T}(Vector{T}(undef, i), 1:i)
end
Base.size(w::TestVector) = (length(w.inds),)
Base.getindex(w::TestVector, i::Integer) = getindex(w.v, i)
function Base.setindex!(w::TestVector, v, i::Integer)
    if i in w.inds 
        setindex!(w.v, v, i)
    else
        v
    end
end
function Base.empty!(w::TestVector)
    empty!(w.v)
    w.inds = 1:0
    return w
end
function Base.resize!(w::TestVector, i::Integer)
    resize!(w.v, i)
    w.inds = 1:i
    return w
end
Base.sizehint!(w::TestVector, i::Integer) = sizehint!(w.v, i)
function Base.pop!(w::TestVector)
    w.inds = 1:length(w.inds)-1
    pop!(w.v)
    return w
end

function Ark.gpuvector_type(::Type{T}, ::Val{:CPU}) where T
    return TestVector{T}
end
function Base.view(tv::TestVector{T}, I::UnitRange) where T
    tv.inds = I
    return tv
end

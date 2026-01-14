
struct TestVector{T} <: AbstractVector{T}
    v::Vector{T}
end
TestVector{T}() where T = TestVector{T}(Vector{T}())
function TestVector{T}(::UndefInitializer, i::Integer) where T
    TestVector{T}(Vector{T}(undef, i))
end
Base.size(w::TestVector) = size(w.v)
Base.getindex(w::TestVector, i::Integer) = getindex(w.v, i)
Base.setindex!(w::TestVector, v, i::Integer) = setindex!(w.v, v, i)
Base.empty!(w::TestVector) = empty!(w.v)
Base.resize!(w::TestVector, i::Integer) = resize!(w.v, i)
Base.sizehint!(w::TestVector, i::Integer) = sizehint!(w.v, i)
Base.pop!(w::TestVector) = pop!(w.v)

function Ark.gpuvector_type(::Type{T}, ::Val{:CPU}) where T
    return TestVector{T}
end
function Base.view(tv::TestVector{T}, I::UnitRange{<:Integer}) where T
    TestVector{T}(tv.v[I])
end

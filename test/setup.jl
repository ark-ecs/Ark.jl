
struct TestVector{T} <: AbstractVector{T}
    v::Vector{T}
end
struct TestVectorView{T} <: AbstractVector{T}
    v::SubArray{T, 1, Vector{T}, Tuple{UnitRange{Int64}}, true}
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

function Ark._gpuvector_type(::Type{T}, ::Val{:CPU}) where T
    return TestVector{T}
end
function Base.view(tv::TestVector{T}, I::UnitRange) where T
    TestVectorView{T}(view(tv.v,I))
end
Base.size(w::TestVectorView) = (length(w.v),)
Base.getindex(w::TestVectorView, i::Integer) = getindex(w.v, i)
Base.setindex!(w::TestVectorView, v, i::Integer) = setindex!(w.v, v, i)
Ark._gpuvectorview_type(v::Type{T}, k::Val{:CPU}) where T = TestVectorView{T}


"""
    FlatVectorView

A linearly indexed view over the component columns of all tables matched by a
[`FlatQuery`](@ref). Elements `1:length(r)` span the tables in table order, so
kernels operate on a single flat index space without knowing about tables:

```julia
@kernel function move_kernel(velocities, dt)
    i = @index(Global)
    velocities[i] += dt
end

q = FlatQuery(world, Filter(world, (Velocity,)))
velocities = q[Velocity]
move_kernel(backend)(velocities, 1.0; ndrange = length(velocities))
```

Each element access resolves its owning table through the offsets, which
costs one extra lookup per access compared to a plain query column. Writes
scatter into the owning table's column. Reductions like `sum`, `maximum` or
`count`, and bulk operations like `fill!` or `copyto!`, are applied per table
and avoid the per-element lookup entirely.

Flat views are passed to kernels like any other argument and are converted to
device memory automatically. Like other GPU storage views, kernels on them run
asynchronously: synchronize the back-end before touching the world again.
"""
struct FlatVectorView{T,PT,OT} <: AbstractVector{T}
    parts::PT
    offsets::OT
    len::Int
    ntables::Int
end

function FlatVectorView{T}(parts, offsets, len::Integer, ntables::Integer) where {T}
    return FlatVectorView{T,typeof(parts),typeof(offsets)}(parts, offsets, Int(len), Int(ntables))
end

Base.length(r::FlatVectorView) = r.len
Base.size(r::FlatVectorView) = (r.len,)
Base.IndexStyle(::Type{<:FlatVectorView}) = IndexLinear()
Base.eltype(::Type{<:FlatVectorView{T}}) where {T} = T

@inline function _find_table(offsets, i::Int)
    n = length(offsets) - 1
    if n <= 32
        t = 1
        off = Int(@inbounds offsets[1])
        @inbounds for k in 2:n
            ok = offsets[k]
            c = Int(Int(ok) < i)
            t += c
            off = ifelse(c == 1, Int(ok), off)
        end
        return t, off
    end
    lo = 1
    hi = n
    @inbounds while lo < hi
        mid = (lo + hi + 1) >>> 1
        if Int(offsets[mid]) < i
            lo = mid
        else
            hi = mid - 1
        end
    end
    return lo, Int(@inbounds offsets[lo])
end

Base.@propagate_inbounds function Base.getindex(r::FlatVectorView, i::Integer)
    i1 = Int(i)
    @boundscheck (1 <= i1 <= r.len) || throw(BoundsError(r, i1))
    if r.ntables == 1
        @inbounds return r.parts[1][i1]
    end
    t, off = _find_table(r.offsets, i1)
    @inbounds return r.parts[t][i1 - off]
end

Base.@propagate_inbounds function Base.setindex!(r::FlatVectorView, v, i::Integer)
    i1 = Int(i)
    @boundscheck (1 <= i1 <= r.len) || throw(BoundsError(r, i1))
    if r.ntables == 1
        @inbounds r.parts[1][i1] = v
        return v
    end
    t, off = _find_table(r.offsets, i1)
    @inbounds r.parts[t][i1 - off] = v
    return v
end

function Adapt.adapt_structure(to, r::FlatVectorView)
    return FlatVectorView{eltype(r)}(
        Adapt.adapt(to, r.parts),
        Adapt.adapt(to, r.offsets),
        r.len,
        r.ntables,
    )
end

function Base.show(io::IO, r::FlatVectorView{T}) where {T}
    return print(io, "$(r.len)-element FlatVectorView{$(_format_type(T))}")
end

# Reductions and bulk operations are applied per table, so each segment is
# processed as contiguous memory without the per-element table lookup.
function Base.mapreduce(f, op, r::FlatVectorView; init = Base._InitialValue(), kwargs...)
    return mapfoldl(
        k -> mapreduce(f, op, @inbounds(r.parts[k]); kwargs...),
        op,
        1:r.ntables;
        init,
    )
end

function Base.fill!(r::FlatVectorView, x)
    for k in 1:r.ntables
        @inbounds fill!(r.parts[k], x)
    end
    return r
end

function _copyto_flat_view!(dest::AbstractVector, src::FlatVectorView)
    length(dest) >= length(src) || throw(BoundsError(dest, length(src)))
    off = 0
    for k in 1:src.ntables
        p = @inbounds src.parts[k]
        n = length(p)
        copyto!(dest, off + 1, p, 1, n)
        off += n
    end
    return dest
end

function _copyto_into_flat_view!(dest::FlatVectorView, src::AbstractVector)
    length(dest) >= length(src) || throw(BoundsError(dest, length(src)))
    off = 0
    for k in 1:dest.ntables
        p = @inbounds dest.parts[k]
        n = length(p)
        copyto!(p, 1, src, off + 1, n)
        off += n
    end
    return dest
end

Base.copyto!(dest::AbstractVector, src::FlatVectorView) = _copyto_flat_view!(dest, src)

Base.copyto!(dest::FlatVectorView, src::AbstractVector) = _copyto_into_flat_view!(dest, src)

Base.copyto!(dest::FlatVectorView, src::FlatVectorView) = _copyto_into_flat_view!(dest, src)

"""
    FlatStructArrayView

The flat analog of a `StructArrayView`: a view over the columns of all tables
matched by a [`FlatQuery`](@ref) for a component stored in a struct-array
storage ([`GPUStructArray`](@ref) or `StructArray`).

Field arrays are accessed by property (e.g. `positions.x`) or with
[`unpack`](@ref unpack(::FlatStructArrayView)), yielding [`FlatVectorView`](@ref)s
that can be passed to kernels. Indexing gathers component values across tables:

```julia
positions = q[Position]
@inbounds positions[1] = Position(0, 0)
```
"""
struct FlatStructArrayView{C,CS<:NamedTuple} <: AbstractArray{C,1}
    _components::CS
end

Base.@propagate_inbounds @generated function Base.getindex(
    sa::FlatStructArrayView{C},
    i::Int,
) where {C}
    names = fieldnames(C)
    comps = :(getfield(sa, :_components))
    first_field = :(getfield($comps, $(QuoteNode(names[1]))))
    single = Expr[:($(name) = @inbounds getfield($comps, $(QuoteNode(name))).parts[1][i]) for name in names]
    multi = Expr[
        :($(name) = @inbounds getfield($comps, $(QuoteNode(name))).parts[t][i - off]) for name in names
    ]
    return quote
        @boundscheck (1 <= i <= length(sa)) || throw(BoundsError(sa, i))
        if $first_field.ntables == 1
            $(Expr(:block, single..., Expr(:new, C, single...)))
        end
        t, off = _find_table($first_field.offsets, i)
        $(Expr(:block, multi..., Expr(:new, C, multi...)))
    end
end

Base.@propagate_inbounds @generated function Base.setindex!(
    sa::FlatStructArrayView{C},
    c::C,
    i::Int,
) where {C}
    names = fieldnames(C)
    comps = :(getfield(sa, :_components))
    first_field = :(getfield($comps, $(QuoteNode(names[1]))))
    single = Expr[
        :(getfield($comps, $(QuoteNode(name))).parts[1][i] = getfield(c, $(QuoteNode(name)))) for name in names
    ]
    multi = Expr[
        :(getfield($comps, $(QuoteNode(name))).parts[t][i - off] = getfield(c, $(QuoteNode(name)))) for
        name in names
    ]
    return quote
        @boundscheck (1 <= i <= length(sa)) || throw(BoundsError(sa, i))
        if $first_field.ntables == 1
            $(Expr(:block, single...))
            return c
        end
        t, off = _find_table($first_field.offsets, i)
        $(Expr(:block, multi...))
        return c
    end
end

@generated function Base.getproperty(sa::FlatStructArrayView{C}, name::Symbol) where {C}
    names = fieldnames(C)
    cases = Expr[
        :(name === $(QuoteNode(n)) && return getfield(sa, :_components).$n) for n in names
    ]
    return Expr(:block, cases..., :(throw(ErrorException(lazy"type $C has no field $name"))))
end

Base.@propagate_inbounds function Base.iterate(sa::FlatStructArrayView{C}) where {C}
    length(sa) == 0 && return nothing
    return sa[1], 2
end

Base.@propagate_inbounds function Base.iterate(sa::FlatStructArrayView{C}, i::Int) where {C}
    i > length(sa) && return nothing
    return sa[i], i + 1
end

Base.size(sa::FlatStructArrayView) = (length(sa),)
Base.length(sa::FlatStructArrayView) = length(first(getfield(sa, :_components)))
Base.eltype(::Type{<:FlatStructArrayView{C}}) where {C} = C
Base.IndexStyle(::Type{<:FlatStructArrayView}) = IndexLinear()
Base.eachindex(sa::FlatStructArrayView) = 1:length(sa)
Base.firstindex(sa::FlatStructArrayView) = 1
Base.lastindex(sa::FlatStructArrayView) = length(sa)

"""
    unpack(a::FlatStructArrayView)

Unpacks the field arrays of a `FlatStructArrayView` returned from a [`FlatQuery`](@ref),
like [`unpack(::StructArrayView)`](@ref) does for query columns.
"""
unpack(a::FlatStructArrayView) = getfield(a, :_components)

@generated function Adapt.adapt_structure(to, sa::FlatStructArrayView{C}) where {C}
    names = fieldnames(C)
    adapted_exprs =
        Expr[:($name = Adapt.adapt(to, getfield(sa, :_components).$name)) for name in names]
    adapted_tuple_expr = Expr(:tuple, adapted_exprs...)
    return quote
        adapted_tuple = $(adapted_tuple_expr)
        FlatStructArrayView{C,typeof(adapted_tuple)}(adapted_tuple)
    end
end

function Base.show(io::IO, sa::FlatStructArrayView{C,CS}) where {C,CS<:NamedTuple}
    names = fieldnames(CS)
    fields_string = join(map(n -> "$(n)::FlatVectorView", names), ", ")
    return print(
        io,
        "$(length(sa))-element FlatStructArrayView($fields_string) with eltype $(_format_type(C))",
    )
end

# Device views of storage memory. The `:CPU` back-end falls back to plain array
# views; back-ends with a GPU provide their own method in the respective interop
# extension.
function _gpuvector_devview end

function _gpuvector_devview(mem::Vector, rng::AbstractUnitRange)
    return view(mem, rng)
end

function _gpuvector_devview(mem, rng::AbstractUnitRange)
    throw(
        ArgumentError(
            lazy"FlatQuery is not supported for the back-end of memory type $(typeof(mem)); use the CPU() back-end or a GPU back-end with FlatQuery support",
        ),
    )
end

# Reusable staging and payload memory for one component field. `devviews` holds
# the per-table device views on the host; `payload` is the uploaded array of
# device views that kernels access through [`FlatVectorView`](@ref).
mutable struct _FieldStaging{B,T,DT,PT}
    const devviews::Vector{DT}
    payload::PT
end

function _FieldStaging(::Val{B}, ::Type{T}) where {B,T}
    dev = _gpuvector_device(Val{B}())
    mem0 = _gpuvector_withdev(() -> _gpuvector_type(T, Val{B}())(undef, 0), dev)
    DT = typeof(_gpuvector_devview(mem0, 1:0))
    PT = _gpuvector_type(DT, Val{B}())
    payload = _gpuvector_withdev(() -> PT(undef, 0), dev)
    return _FieldStaging{B,T,DT,PT}(DT[], payload)
end

@inline function _grow_payload!(f::_FieldStaging{B}, cap::Int) where {B}
    if length(f.payload) < cap
        PT = typeof(f.payload)
        f.payload = _gpuvector_withdev(() -> PT(undef, cap), _gpuvector_device(Val{B}()))
    end
    return f
end

@inline _fields_of(col::GPUVector) = (col,)
@inline _fields_of(col::GPUStructArray) = Tuple(getfield(col, :_components))
@inline _fields_of(col::_AbstractStructArray) = Tuple(getfield(col, :_components))
@inline _fields_of(col) = (col,)

# Host storages (any AbstractVector other than the GPU storages) are exposed
# through lazy contiguous views, which work for custom storages without a
# `view` method.
struct _ColumnView{C,P<:AbstractVector{C}} <: AbstractVector{C}
    parent::P
    len::Int
end

_ColumnView(parent::AbstractVector{C}) where {C} = _ColumnView{C,typeof(parent)}(parent, length(parent))

Base.length(v::_ColumnView) = v.len
Base.size(v::_ColumnView) = (v.len,)
Base.IndexStyle(::Type{<:_ColumnView}) = IndexLinear()
Base.@propagate_inbounds Base.getindex(v::_ColumnView, i::Int) = v.parent[i]
Base.@propagate_inbounds function Base.setindex!(v::_ColumnView, x, i::Int)
    @inbounds v.parent[i] = x
    return x
end

@inline _is_gpu_storage(::Type{A}) where {A} = A <: GPUVector || A <: GPUStructArray

_components_ntype(::Type{<:_AbstractStructArray{C,CS}}) where {C,CS} = CS

# Column view types of the component fields of a host storage, as exposed to kernels.
@inline function _host_field_view_types(::Type{A}) where {A<:AbstractArray}
    if A <: _AbstractStructArray
        return Tuple(_ColumnView{eltype(ft),ft} for ft in fieldtypes(_components_ntype(A)))
    end
    return (_ColumnView{eltype(A),A},)
end

const _EntitiesPart = SubArray{Entity,1,Vector{Entity},Tuple{UnitRange{Int}},true}

mutable struct FlatQuery{F<:Filter,ST<:Tuple,FS<:Tuple,V<:Tuple}
    const _filter::F
    const _storages::ST
    const _fstates::FS
    const _offsets_staging::Vector{Int32}
    _offsets_payload
    _views::V
    const _entities_parts::Vector{_EntitiesPart}
    _entities
    const _buf::Vector{UInt32}
    const _sig_ids::Vector{UInt32}
    const _sig_lens::Vector{Int}
    const _sig_ptrs::Vector{UInt}
    _cap::Int
    _ntables::Int
    _len::Int
end

"""
    FlatQuery(world::World, filter::Filter)

Creates a flat query over all tables matching the given [Filter](@ref), e.g. to
launch a single GPU kernel over all of them instead of one kernel per table, as
[Query](@ref) iteration would.

A flat query is a long-lived handle that re-derives its contents whenever it is
accessed, so it stays valid across structural changes of the world. It provides
one flat, linearly indexed view per filtered component spanning all matching
tables: `q[Comp]` returns a [`FlatVectorView`](@ref), or a
[`FlatStructArrayView`](@ref) for components stored in a [`GPUStructArray`](@ref).
`length(q)` is the total number of matched entities. The entity ids of all
matching tables are available via `q[Entity]`.

Components may use any storage. If any component uses a GPU storage
([`GPUVector`](@ref) or [`GPUStructArray`](@ref)), all components must use GPU
storages with the same back-end. Components with other storages (e.g. `Vector`
or `StructArray`) live in host memory, so kernels launched on their views are
restricted to the `CPU()` back-end. Optional components are not supported. The
entity views are backed by host memory and are meant for host-side access;
kernels should use only the component views.

The returned views reference the storages directly and copy no component data.
When the filter matches a single table, views have no lookup overhead at all.
For multiple matching tables, element access on a view costs one extra offset
lookup compared to a plain query column.

Views taken from the flat query must not be kept across structural changes of
the world: re-read them after modifying it.

Like with queries, kernels launched on the views execute asynchronously; see
[Synchronization with GPU Storages](@ref gpu-storage-synchronization).

The views can also be destructured in filter order, with the entity ids last:

```julia
q = FlatQuery(world, Filter(world, (Position, Velocity)))
positions, velocities = q # component views, without entities
entities, positions, velocities = q # with entity ids

positions = q[Position]
velocities = q[Velocity]
move_kernel(backend)(positions, velocities, 0.1f0; ndrange = length(q))
KernelAbstractions.synchronize(backend)
```
"""
function FlatQuery(world::W, filter::F) where {W<:World,F<:Filter}
    _check_filter_world(world, filter)
    if !isempty(_active_bit_indices(_filter_optional_mask(F)))
        throw(ArgumentError("optional components are not supported by FlatQuery"))
    end
    storages = _flatquery_storages(world, F)
    return _FlatQuery_from_storages(filter, storages)
end

@generated function _flatquery_storages(world::W, ::Type{F}) where {W<:World,F<:Filter}
    Storage = _world_storage(W)
    # Relation targets are filter criteria only; they have no column views.
    rel_types = _world_relation_types(W)
    ids = Int[
        id for id in _filter_output_ids(F) if
        !_is_relation_type(_component_type(fieldtype(_schema_storage_types(Storage), id)), rel_types)
    ]
    exprs = Expr[_storage_ref(:stores, Storage, id) for id in ids]
    return quote
        stores = _storage(world)
        ($(exprs...),)
    end
end


@inline function _field_eltypes(::Type{<:GPUVector{B,T}}) where {B,T}
    return (T,)
end

@inline function _field_eltypes(::Type{<:GPUStructArray{B,C,CS}}) where {B,C,CS}
    return Tuple(eltype(S) for S in fieldtypes(CS))
end

function _offsets_payload_type(::Type{A}) where {A<:Union{GPUVector,GPUStructArray}}
    return _gpuvector_type(Int32, Val{_gpu_backend(A)}())
end

function _FlatQuery_from_storages(filter::F, storages::ST) where {F<:Filter,ST<:Tuple}
    isempty(storages) && throw(ArgumentError("FlatQuery requires at least one component"))
    gpu_mode = any(_is_gpu_storage ∘ eltype, storages)
    backend = nothing
    if gpu_mode
        backend = _gpu_backend(eltype(first(s for s in storages if _is_gpu_storage(eltype(s)))))
        for cols in storages
            A = eltype(cols)
            _is_gpu_storage(A) || throw(ArgumentError(
                "FlatQuery requires all components to use GPU storages when any component uses a GPU storage",
            ))
            _gpu_backend(A) == backend ||
                throw(ArgumentError("FlatQuery requires all components to use the same back-end"))
        end
    end

    fstates = map(storages) do cols
        A = eltype(cols)
        if _is_gpu_storage(A)
            return map(_field_eltypes(A)) do T
                _FieldStaging(Val{_gpu_backend(A)}(), T)
            end
        end
        return map(_host_field_view_types(A)) do DT
            DT[]
        end
    end

    offsets_staging = Int32[0]
    if gpu_mode
        OT = _offsets_payload_type(eltype(first(storages)))
        offsets_payload = _gpuvector_withdev(() -> OT(undef, 1), _gpuvector_device(Val{backend}()))
    else
        offsets_payload = offsets_staging
    end

    # Views have stable types across refreshes: payloads are replaced with
    # same-typed allocations on growth, never re-typed.
    views = map(storages, fstates) do cols, fst
        if _is_gpu_storage(eltype(cols))
            return _make_view(eltype(cols), fst, offsets_payload, 0, 0)
        end
        return _make_host_view(eltype(cols), fst, offsets_staging, 0, 0)
    end

    b = FlatQuery(
        filter,
        storages,
        fstates,
        offsets_staging,
        offsets_payload,
        views,
        _EntitiesPart[],
        FlatVectorView{Entity}(_EntitiesPart[], offsets_staging, 0, 0),
        UInt32[],
        UInt32[],
        Int[],
        UInt[],
        0,
        0,
        0,
    )
    _refresh!(b)
    return b
end

function _make_view(::Type{A}, fstates::NTuple{1,_FieldStaging}, offsets, len::Int, ntables::Int) where {A<:GPUVector}
    T = eltype(A)
    return FlatVectorView{T}(fstates[1].payload, offsets, len, ntables)
end

function _make_view(
    ::Type{A},
    fstates::NTuple{N,_FieldStaging},
    offsets,
    len::Int,
    ntables::Int,
) where {B,C,N,A<:GPUStructArray{B,C}}
    flatviews = map(fstates) do fst
        T = eltype(eltype(fst.payload))
        return FlatVectorView{T}(fst.payload, offsets, len, ntables)
    end
    nt = NamedTuple{fieldnames(C)}(flatviews)
    return FlatStructArrayView{C,typeof(nt)}(nt)
end

function _make_host_view(
    ::Type{A},
    parts::NTuple{1,Vector{DT}},
    offsets,
    len::Int,
    ntables::Int,
) where {A,DT<:_ColumnView}
    return FlatVectorView{eltype(DT)}(parts[1], offsets, len, ntables)
end

function _make_host_view(
    ::Type{A},
    parts::NTuple{N,Vector{DT}},
    offsets,
    len::Int,
    ntables::Int,
) where {C,CS,N,A<:_AbstractStructArray{C,CS},DT<:_ColumnView}
    flatviews = map(parts) do p
        return FlatVectorView{eltype(DT)}(p, offsets, len, ntables)
    end
    nt = NamedTuple{fieldnames(C)}(flatviews)
    return FlatStructArrayView{C,typeof(nt)}(nt)
end

Base.length(b::FlatQuery) = ((_refresh!(b); b._len))

@generated function Base.getindex(b::FlatQuery, ::Type{C}) where {C}
    views = fieldtype(b, :_views)
    comp_types = map(vt -> eltype(vt), fieldtypes(views))
    for (i, ct) in enumerate(comp_types)
        if ct === C
            return quote
                _refresh!(b)
                getfield(b, :_views)[$i]
            end
        end
    end
    available = join(map(_format_type, comp_types), ", ")
    return :(throw(
        ArgumentError(
            "component " *
            _format_type(C) *
            " is not part of this FlatQuery; available components: " * $available,
        ),
    ))
end

function Base.show(io::IO, b::FlatQuery{F}) where {F<:Filter}
    storages = b._storages
    comp_types = Tuple(_component_type(eltype(cols)) for cols in storages)
    types_string = join(map(_format_type, comp_types), ", ")
    return print(
        io,
        "FlatQuery(entities=$(b._len), tables=$(b._ntables), comp_types=($types_string))",
    )
end

# Iteration yields the component views in filter order, followed by the entity
# ids, so a flat query can be destructured both with and without entities:
# `positions, velocities = q` or `entities, positions, velocities = q`.
function Base.iterate(b::FlatQuery)
    _refresh!(b)
    return iterate(getfield(b, :_views))
end

function Base.iterate(b::FlatQuery, state::Int)
    views = getfield(b, :_views)
    state <= length(views) && return iterate(views, state)
    state == length(views) + 1 && return (b._entities, state + 1)
    return nothing
end

function Base.getindex(b::FlatQuery, ::Type{Entity})
    _refresh!(b)
    return b._entities
end

# Scans the world for all non-empty tables matching the filter into `b._buf`,
# mirroring query iteration (including relation filtering within archetypes).
function _scan_tables!(b::FlatQuery)
    state = b._filter._world_state
    filter = b._filter._filter
    buf = b._buf
    empty!(buf)

    if _is_cached(filter)
        for id in filter.tables.ids
            table = state._tables[Int(id)]
            isempty(table.entities) && continue
            push!(buf, id)
        end
        return buf
    end

    arches, arches_hot = _get_archetypes(state, b._filter)
    for i in eachindex(arches)
        archetype_hot = @inbounds arches_hot[i]
        if !_matches(filter, archetype_hot)
            continue
        end
        if !archetype_hot.has_relations
            table = @inbounds state._tables[Int(archetype_hot.table)]
            isempty(table.entities) && continue
            push!(buf, table.id)
            continue
        end
        archetype = @inbounds arches[i]
        isempty(archetype.tables) && continue
        tables = _get_tables(state, archetype, filter.relations)
        for table_id in tables
            table = @inbounds state._tables[Int(table_id)]
            if !isempty(table.entities) && _matches(state._relations, table, filter.relations)
                push!(buf, table.id)
            end
        end
    end
    return buf
end

function _refresh!(b::FlatQuery)
    _scan_tables!(b)
    _changed(b) || return b
    _rebuild!(b)
    return b
end

# Detects whether any matching table id, table length or column memory location
# changed since the last build. Assumes `b._buf` was just re-scanned.
function _changed(b::FlatQuery)
    T = length(b._buf)
    sig_ids = b._sig_ids
    length(sig_ids) == T || return true
    sig_lens = b._sig_lens
    sig_ptrs = b._sig_ptrs
    fi = 0
    for cols in b._storages
        gpu = _is_gpu_storage(eltype(cols))
        for k in 1:T
            table_id = Int(b._buf[k])
            table = b._filter._world_state._tables[table_id]
            (k <= length(sig_lens) && sig_lens[k] == length(table.entities)) || return true
            sig_ids[k] == b._buf[k] || return true
            col = cols[table_id]
            for f in _fields_of(col)
                fi += 1
                sig = gpu ? UInt(pointer(getfield(f, :mem))) : UInt(objectid(f))
                (fi <= length(sig_ptrs) && sig_ptrs[fi] == sig) || return true
            end
        end
    end
    return false
end

function _rebuild!(b::FlatQuery)
    state = b._filter._world_state
    buf = b._buf
    T = length(buf)
    gpu_mode = any(_is_gpu_storage ∘ eltype, b._storages)

    if gpu_mode && b._cap < T
        new_cap = max(T, 2 * b._cap)
        for fstates in b._fstates
            for f in fstates
                _grow_payload!(f, new_cap)
            end
        end
        OT = typeof(b._offsets_payload)
        backend = _gpu_backend(eltype(first(b._storages)))
        b._offsets_payload =
            _gpuvector_withdev(() -> OT(undef, new_cap + 1), _gpuvector_device(Val{backend}()))
        b._cap = new_cap
    end

    # Offsets: table t covers global indices (offsets[t], offsets[t+1]].
    offsets = b._offsets_staging
    length(offsets) < T + 1 && resize!(offsets, T + 1)
    offset = Int32(0)
    for k in 1:T
        @inbounds offsets[k] = offset
        offset += length(state._tables[Int(buf[k])].entities)
    end
    @inbounds offsets[T+1] = offset
    if gpu_mode
        copyto!(b._offsets_payload, 1, offsets, 1, T + 1)
    end

    # Stage per-table views, upload them for GPU storages, and refresh the signature.
    resize!(b._sig_ids, T)
    resize!(b._sig_lens, T)
    resize!(b._sig_ptrs, 0)
    map(b._storages, b._fstates) do cols, fstates
        if _is_gpu_storage(eltype(cols))
            for f in fstates
                resize!(f.devviews, T)
            end
            for k in 1:T
                table_id = Int(buf[k])
                table = state._tables[table_id]
                b._sig_lens[k] = length(table.entities)
                col = cols[table_id]
                fields = _fields_of(col)
                foreach(fields, fstates) do f, fst
                    push!(b._sig_ptrs, UInt(pointer(getfield(f, :mem))))
                    fst.devviews[k] = _gpuvector_devview(getfield(f, :mem), 1:length(table.entities))
                end
            end
            for f in fstates
                copyto!(f.payload, 1, f.devviews, 1, T)
            end
        else
            for parts in fstates
                resize!(parts, T)
            end
            for k in 1:T
                table_id = Int(buf[k])
                table = state._tables[table_id]
                b._sig_lens[k] = length(table.entities)
                col = cols[table_id]
                fields = _fields_of(col)
                foreach(fields, fstates) do f, parts
                    push!(b._sig_ptrs, UInt(objectid(f)))
                    parts[k] = _ColumnView(f)
                end
            end
        end
        return nothing
    end
    copyto!(b._sig_ids, 1, buf, 1, T)

    b._views = map(b._storages, b._fstates) do cols, fstates
        if _is_gpu_storage(eltype(cols))
            return _make_view(eltype(cols), fstates, b._offsets_payload, Int(offset), T)
        end
        return _make_host_view(eltype(cols), fstates, b._offsets_staging, Int(offset), T)
    end

    # Entity views reference host memory directly; growth of a table's entity
    # column always changes its length, so the signature length check covers it.
    resize!(b._entities_parts, T)
    for k in 1:T
        table = state._tables[Int(buf[k])]
        b._entities_parts[k] = view(table.entities._data, 1:length(table.entities))
    end
    b._entities = FlatVectorView{Entity}(b._entities_parts, b._offsets_staging, Int(offset), T)

    b._ntables = T
    b._len = Int(offset)
    return b
end

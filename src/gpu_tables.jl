
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

# Finds the table `t` owning global index `i`, and its offset. Only the first
# `n + 1` offsets are valid: the device copy of the offsets may be larger.
# The branchless linear scan only beats binary search for very few tables; from
# about 8 tables on, it is increasingly slower on both GPU and CPU.
@inline function _find_table(offsets, n::Int, i::Int)
    if n <= 4
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
    t, off = _find_table(r.offsets, r.ntables, i1)
    @inbounds return r.parts[t][i1 - off]
end

Base.@propagate_inbounds function Base.setindex!(r::FlatVectorView, v, i::Integer)
    i1 = Int(i)
    @boundscheck (1 <= i1 <= r.len) || throw(BoundsError(r, i1))
    if r.ntables == 1
        @inbounds r.parts[1][i1] = v
        return v
    end
    t, off = _find_table(r.offsets, r.ntables, i1)
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

# The inlining and bounds-check propagation meta must be part of the generated
# code: `Base.@propagate_inbounds` on a generated function only reaches the
# generator. Without it, element access is a call per element, which is
# particularly slow in GPU kernels.
@generated function Base.getindex(
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
        $(Expr(:meta, :inline, :propagate_inbounds))
        @boundscheck (1 <= i <= length(sa)) || throw(BoundsError(sa, i))
        if $first_field.ntables == 1
            $(Expr(:block, single..., Expr(:return, Expr(:new, C, single...))))
        end
        t, off = _find_table($first_field.offsets, $first_field.ntables, i)
        $(Expr(:block, multi..., Expr(:new, C, multi...)))
    end
end

@generated function Base.setindex!(
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
        $(Expr(:meta, :inline, :propagate_inbounds))
        @boundscheck (1 <= i <= length(sa)) || throw(BoundsError(sa, i))
        if $first_field.ntables == 1
            $(Expr(:block, single...))
            return c
        end
        t, off = _find_table($first_field.offsets, $first_field.ntables, i)
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

# Migrates the first `n` elements of storage memory to the device ahead of
# kernel launches. Kernels on flat views reach the storages through device views,
# so back-ends only prefetch their payload at launch, not the storage memory.
# Back-ends with migrating unified memory provide a method in their interop
# extension; the fallback does nothing.
_gpuvector_prefetch(mem, n::Int) = nothing

# Reusable staging and payload memory for one component field. `devviews` holds
# the per-table device views on the host; `payload` is the uploaded array of
# device views that kernels access through [`FlatVectorView`](@ref). After each
# staging, `payload` mirrors `devviews`, so unchanged views skip the upload.
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

# Grows the payload geometrically to hold at least `n` views. Returns whether it
# was replaced, in which case its contents must be uploaded again.
@inline function _grow_payload!(f::_FieldStaging{B}, n::Int) where {B}
    length(f.payload) >= n && return false
    PT = typeof(f.payload)
    cap = max(n, 2 * length(f.payload))
    f.payload = _gpuvector_withdev(() -> PT(undef, cap), _gpuvector_device(Val{B}()))
    return true
end

# The world's GPU storage types leave the memory type of their vectors open, so
# it is asserted from the back-end and element type to keep staging type-stable.
@inline function _gpuvector_mem(v::GPUVector{B,T}) where {B,T}
    return getfield(v, :mem)::_gpuvector_type(T, Val{B}())
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

@inline function _field_eltypes(::Type{<:GPUVector{B,T}}) where {B,T}
    return (T,)
end

@inline function _field_eltypes(::Type{<:GPUStructArray{B,C,CS}}) where {B,C,CS}
    return Tuple(eltype(S) for S in fieldtypes(CS))
end

# The GPU back-end shared by all component storages of a flat query, or `nothing`
# if all of them live in host memory. Rejects mixed GPU and host storages.
@generated function _flat_backend(::Type{ST}) where {ST<:Tuple}
    storage_types = Any[eltype(S) for S in fieldtypes(ST)]
    any(_is_gpu_storage, storage_types) || return :(nothing)
    if !all(_is_gpu_storage, storage_types)
        return :(throw(ArgumentError(
            "FlatQuery requires all components to use GPU storages when any component uses a GPU storage",
        )))
    end
    backends = unique(Any[_gpu_backend(A) for A in storage_types])
    if length(backends) > 1
        return :(throw(ArgumentError("FlatQuery requires all components to use the same back-end")))
    end
    return :(Val{$(QuoteNode(backends[1]))}())
end

# Per-field staging memory for each component storage: `_FieldStaging`s for GPU
# storages, vectors of per-table column views for host storages.
@generated function _new_fstates(::Type{ST}) where {ST<:Tuple}
    exprs = map(fieldtypes(ST)) do S
        A = eltype(S)
        if _is_gpu_storage(A)
            B = QuoteNode(_gpu_backend(A))
            return Expr(:tuple, (:(_FieldStaging(Val{$B}(), $T)) for T in _field_eltypes(A))...)
        end
        return Expr(:tuple, (:($DT[]) for DT in _host_field_view_types(A))...)
    end
    return Expr(:tuple, exprs...)
end

const _EntitiesPart = SubArray{Entity,1,Vector{Entity},Tuple{UnitRange{Int}},true}

# Reusable memory of a flat query. Flat queries over the same storages and
# filter masks share a pool of buffers in the world, so that only the first one
# allocates. An open flat query owns its buffers exclusively and returns them
# to the pool on `close!`. Each release increments `session`, so a closed flat
# query stays closed when its buffers are reused.
mutable struct _FlatBuffers{FS<:Tuple,OP<:AbstractVector{Int32}}
    const fstates::FS
    const tables::Vector{UInt32}
    const offsets::Vector{Int32}
    offsets_payload::OP
    const entities_parts::Vector{_EntitiesPart}
    const pool::Vector{Any}
    session::Int
end

function _new_flat_buffers(::Type{ST}, pool::Vector{Any}) where {ST<:Tuple}
    offsets = Int32[]
    return _FlatBuffers(
        _new_fstates(ST),
        UInt32[],
        offsets,
        _new_offsets_payload(_flat_backend(ST), offsets),
        _EntitiesPart[],
        pool,
        0,
    )
end

# Host storages index the staged offsets directly.
_new_offsets_payload(::Nothing, offsets::Vector{Int32}) = offsets

function _new_offsets_payload(::Val{B}, ::Vector{Int32}) where {B}
    OT = _gpuvector_type(Int32, Val{B}())
    return _gpuvector_withdev(() -> OT(undef, 0), _gpuvector_device(Val{B}()))
end

# Like queries, flat queries may be created and closed from multiple threads.
function _acquire_flat_buffers(state::_WorldState, filter::_MaskFilter, ::Type{ST}) where {ST<:Tuple}
    pools = state._pool
    local pool, buffers
    @_maybe_locked pools.flat_buffers_lock begin
        pool = get!(() -> Any[], pools.flat_buffers, (ST, filter.mask, filter.exclude_mask))
        buffers = isempty(pool) ? nothing : pop!(pool)
    end
    buffers === nothing && return _new_flat_buffers(ST, pool)
    return buffers::Base.promote_op(_new_flat_buffers, Type{ST}, Vector{Any})
end

struct FlatQuery{F<:Filter,ST<:Tuple,B<:_FlatBuffers,V<:Tuple,E<:FlatVectorView}
    _filter::F
    _storages::ST
    _buffers::B
    _views::V
    _entities::E
    _ntables::Int
    _len::Int
    _session::Int
end

"""
    FlatQuery(world::World, filter::Filter; prefetch::Bool = true)

Creates a flat query over all tables matching the given [Filter](@ref), e.g. to
launch a single GPU kernel over all of them instead of one kernel per table, as
[Query](@ref) iteration would.

The flat query [locks](@ref world-lock) the world at construction and builds all
views once. It provides one flat, linearly indexed view per filtered component
spanning all matching tables: `q[Comp]` returns a [`FlatVectorView`](@ref), or a
[`FlatStructArrayView`](@ref) for components stored in a struct-array storage.
`length(q)` is the total number of matched entities. The entity ids of all
matching tables are available via `q[Entity]`.

While the flat query is open, structural operations like `new_entity!` or
`add_components!` throw an error, so the views are guaranteed to stay valid.
Call [`close!`](@ref close!(::FlatQuery)) to unlock the world; the flat query
can't be used anymore afterwards.

Flat queries are meant to be re-created whenever they are needed, e.g. once per
frame: `close!` hands the flat query's internal buffers back to the world, and
the next flat query with the same components and filter criteria reuses them.
Only the first flat query allocates, apart from creating the [Filter](@ref). For
GPU storages, the table layout is only uploaded to the device again after
structural changes of the matching tables.

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

Like with queries, kernels launched on the views execute asynchronously; see
[Synchronization with GPU Storages](@ref gpu-storage-synchronization). The world
must not be modified while kernels are still in flight, even after closing the
flat query - synchronize the back-end first.

With `prefetch`, the matched component memory is migrated to the device when the
flat query is created, on back-ends with migrating unified memory (currently
CUDA). Kernels reach the components through the flat views only indirectly, so
the back-end can't prefetch them at launch as it does for query columns. This
avoids slow on-demand page migration in kernels after components were accessed
from the host, e.g. for rendering. If the components are only ever accessed by
kernels, `prefetch = false` saves the prefetch calls (a few microseconds per
table and field).

The views can also be destructured in filter order, with the entity ids last:

```julia
q = FlatQuery(world, Filter(world, (Position, Velocity)))
positions, velocities = q # component views, without entities
positions, velocities, entities = q # with entity ids

positions = q[Position]
velocities = q[Velocity]
move_kernel(backend)(positions, velocities, 0.1f0; ndrange = length(q))
KernelAbstractions.synchronize(backend)
close!(q)
```
"""
function FlatQuery(world::W, filter::F; prefetch::Bool = true) where {W<:World,F<:Filter}
    _check_filter_world(world, filter)
    if _is_not_zero(_filter_optional_mask(F))
        throw(ArgumentError("optional components are not supported by FlatQuery"))
    end
    storages = _flatquery_storages(world, F)
    isempty(storages) && throw(ArgumentError("FlatQuery requires at least one component"))
    _flat_backend(typeof(storages)) # rejects mixed storages before locking
    state = filter._world_state
    buffers = _acquire_flat_buffers(state, filter._filter, typeof(storages))
    _lock(state._lock)
    q = try
        _FlatQuery_from_buffers(filter, storages, buffers, prefetch)
    catch
        # The buffers may be partially staged, so they are not returned to the pool.
        _unlock(state._lock)
        rethrow()
    end
    return q
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

function _FlatQuery_from_buffers(filter::Filter, storages::ST, buffers::_FlatBuffers, prefetch::Bool) where {ST<:Tuple}
    state = filter._world_state
    tables = _scan_tables!(buffers.tables, state, filter)
    ntables = length(tables)
    len = _stage_offsets!(buffers, state, _flat_backend(ST))

    map(storages, buffers.fstates) do cols, fstates
        return _stage_columns!(fstates, cols, state, tables, prefetch)
    end

    entities_parts = buffers.entities_parts
    resize!(entities_parts, ntables)
    for k in 1:ntables
        table = state._tables[Int(tables[k])]
        entities_parts[k] = view(table.entities._data, 1:length(table.entities))
    end
    entities = FlatVectorView{Entity}(entities_parts, buffers.offsets, len, ntables)

    views = map(storages, buffers.fstates) do cols, fstates
        if _is_gpu_storage(eltype(cols))
            return _make_view(eltype(cols), fstates, buffers.offsets_payload, len, ntables)
        end
        return _make_host_view(eltype(cols), fstates, buffers.offsets_payload, len, ntables)
    end

    return FlatQuery(filter, storages, buffers, views, entities, ntables, len, buffers.session)
end

# Stages the offsets of the scanned tables, where table t covers the global
# indices (offsets[t], offsets[t+1]]. Returns the total number of entities.
function _stage_offsets!(buffers::_FlatBuffers, state::_WorldState, backend)
    tables = buffers.tables
    offsets = buffers.offsets
    ntables = length(tables)
    changed = length(offsets) != ntables + 1
    resize!(offsets, ntables + 1)
    offset = 0
    for k in 1:ntables
        changed = changed || @inbounds(offsets[k]) != offset
        @inbounds offsets[k] = offset
        offset += length(state._tables[Int(tables[k])].entities)
    end
    changed = changed || @inbounds(offsets[ntables+1]) != offset
    @inbounds offsets[ntables+1] = offset
    _upload_offsets!(buffers, backend, changed)
    return offset
end

_upload_offsets!(::_FlatBuffers, ::Nothing, ::Bool) = nothing

function _upload_offsets!(buffers::_FlatBuffers, ::Val{B}, changed::Bool) where {B}
    offsets = buffers.offsets
    n = length(offsets)
    if length(buffers.offsets_payload) < n
        OT = typeof(buffers.offsets_payload)
        cap = max(n, 2 * length(buffers.offsets_payload))
        buffers.offsets_payload = _gpuvector_withdev(() -> OT(undef, cap), _gpuvector_device(Val{B}()))
        changed = true
    end
    changed && copyto!(buffers.offsets_payload, 1, offsets, 1, n)
    return nothing
end

# Stages the per-table views of each field of a component storage.
@generated function _stage_columns!(
    fstates::Tuple,
    cols::Vector,
    state::_WorldState,
    tables::Vector{UInt32},
    prefetch::Bool,
)
    calls = Expr[:(_stage_field!(fstates[$i], cols, Val($i), state, tables, prefetch)) for i in 1:fieldcount(fstates)]
    return Expr(:block, calls..., :(return nothing))
end

# Stages the device views of field `I` of a GPU storage, and uploads them if
# they changed since the buffers were last used.
function _stage_field!(
    f::_FieldStaging,
    cols::Vector,
    ::Val{I},
    state::_WorldState,
    tables::Vector{UInt32},
    prefetch::Bool,
) where {I}
    ntables = length(tables)
    changed = length(f.devviews) != ntables
    resize!(f.devviews, ntables)
    for k in 1:ntables
        table = state._tables[Int(tables[k])]
        mem = _gpuvector_mem(_fields_of(cols[table.id])[I])
        prefetch && _gpuvector_prefetch(mem, length(table.entities))
        v = _gpuvector_devview(mem, 1:length(table.entities))
        changed = changed || @inbounds(f.devviews[k]) !== v
        @inbounds f.devviews[k] = v
    end
    if (_grow_payload!(f, ntables) | changed) && ntables > 0
        copyto!(f.payload, 1, f.devviews, 1, ntables)
    end
    return nothing
end

# Host storages are exposed through lazy column views, which need no upload.
function _stage_field!(
    parts::Vector{<:_ColumnView},
    cols::Vector,
    ::Val{I},
    state::_WorldState,
    tables::Vector{UInt32},
    ::Bool,
) where {I}
    resize!(parts, length(tables))
    for k in eachindex(tables)
        table = state._tables[Int(tables[k])]
        @inbounds parts[k] = _ColumnView(_fields_of(cols[table.id])[I])
    end
    return nothing
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

@inline function _check_not_closed(b::FlatQuery)
    if b._buffers.session != b._session
        throw(InvalidStateException("flat query closed, it can't be used anymore", :query_closed))
    end
    return nothing
end

Base.length(b::FlatQuery) = ((_check_not_closed(b); b._len))

@generated function Base.getindex(b::FlatQuery, ::Type{C}) where {C}
    views = fieldtype(b, :_views)
    comp_types = map(vt -> eltype(vt), fieldtypes(views))
    for (i, ct) in enumerate(comp_types)
        if ct === C
            return quote
                _check_not_closed(b)
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
    _check_not_closed(b)
    return iterate(getfield(b, :_views))
end

function Base.iterate(b::FlatQuery, state::Int)
    views = getfield(b, :_views)
    state <= length(views) && return iterate(views, state)
    state == length(views) + 1 && return (b._entities, state + 1)
    return nothing
end

function Base.getindex(b::FlatQuery, ::Type{Entity})
    _check_not_closed(b)
    return b._entities
end

"""
    close!(q::FlatQuery)

Closes the flat query and unlocks the world, so that structural operations can
be performed again. The flat query can't be used anymore afterwards.

Closing hands the flat query's internal buffers back to the world, for reuse by
the next flat query with the same components and filter criteria.
"""
function close!(q::FlatQuery)
    buffers = q._buffers
    buffers.session == q._session || return nothing
    buffers.session += 1
    state = q._filter._world_state
    _unlock(state._lock)
    @_maybe_locked state._pool.flat_buffers_lock push!(buffers.pool, buffers)
    return nothing
end

# Scans the world for all non-empty tables matching the filter into `buf`,
# mirroring query iteration (including relation filtering within archetypes).
function _scan_tables!(buf::Vector{UInt32}, state::_WorldState, f::Filter)
    filter = f._filter
    empty!(buf)
    if _is_cached(filter)
        for id in filter.tables.ids
            table = state._tables[Int(id)]
            isempty(table.entities) && continue
            push!(buf, id)
        end
        return buf
    end

    arches, arches_hot = _get_archetypes(state, f)
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


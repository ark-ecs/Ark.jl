
# Type-erased per-component dispatch.
#
# By default a `World` resolves the component index of a runtime operation with one
# `if comp == i` branch per component type (see `_generate_component_switch`). The
# resulting code is optimal, but its size grows with the number of component types, and
# compiling it dominates latency for worlds that declare many components.
#
# A world created with `mode=:boxed` routes those operations through vectors of
# `FunctionWrapper`s instead - one wrapper per component storage - so the size of the
# generated code no longer depends on the number of component types. Wrappers are built
# lazily, per operation and per component, so a world only ever compiles the combinations
# it actually performs.

const _FW_ActivateColumn = FunctionWrapper{Nothing,Tuple{Int,Int}}
const _FW_EnsureColumnSize = FunctionWrapper{Nothing,Tuple{UInt32,Int}}
const _FW_MoveData = FunctionWrapper{Nothing,Tuple{UInt32,UInt32,UInt32}}
const _FW_CopyData = FunctionWrapper{Nothing,Tuple{UInt32,UInt32,UInt32}}
const _FW_CopyDataToEnd = FunctionWrapper{Nothing,Tuple{UInt32,UInt32}}
const _FW_ClearColumn = FunctionWrapper{Nothing,Tuple{UInt32}}
const _FW_RemoveData = FunctionWrapper{Nothing,Tuple{UInt32,UInt32}}
const _FW_SwapData = FunctionWrapper{Nothing,Tuple{UInt32,Int,Int}}
const _FW_PermuteCycle = FunctionWrapper{Nothing,Tuple{UInt32,Entities,Vector{_EntityIndex},Int}}

# One callable per storage operation. A `FunctionWrapper` can only wrap a callable value,
# and a generated function may not emit closures, so the storage is captured in a struct.
# Column lifecycle needs both halves of a storage; everything else only needs the columns.
struct _ActivateColumnOp{S,E}
    storage::S
    empty::E
end
struct _EnsureColumnSizeOp{S,E}
    storage::S
    empty::E
end
struct _MoveDataOp{S}
    storage::S
end
struct _CopyDataOp{S,CP<:Val}
    storage::S
    mode::CP
end
struct _CopyDataToEndOp{S}
    storage::S
end
struct _ClearColumnOp{S,E}
    storage::S
    empty::E
end
struct _RemoveDataOp{S}
    storage::S
end
struct _SwapDataOp{S}
    storage::S
end
struct _PermuteCycleOp{S}
    storage::S
end

(op::_ActivateColumnOp)(index::Int, cap::Int) = _activate_column!(op.storage, op.empty, index, cap)
(op::_EnsureColumnSizeOp)(arch::UInt32, needed::Int) =
    _ensure_column_size!(op.storage, op.empty, arch, needed)
(op::_MoveDataOp)(old_table::UInt32, new_table::UInt32, row::UInt32) =
    _move_component_data!(op.storage, old_table, new_table, row)
(op::_CopyDataOp)(old_table::UInt32, new_table::UInt32, old_row::UInt32) =
    _copy_component_data!(op.storage, old_table, new_table, old_row, op.mode)
(op::_CopyDataToEndOp)(old_table::UInt32, new_table::UInt32) =
    _copy_component_data_to_end!(op.storage, old_table, new_table)
(op::_ClearColumnOp)(table::UInt32) = _clear_column!(op.storage, op.empty, table)
(op::_RemoveDataOp)(table::UInt32, row::UInt32) = _remove_component_data!(op.storage, table, row)
(op::_SwapDataOp)(table::UInt32, i::Int, j::Int) = _swap_component_data!(op.storage, table, i, j)
(op::_PermuteCycleOp)(table::UInt32, entities::Entities, entity_index::Vector{_EntityIndex}, start::Int) =
    _permute_component_cycle!(op.storage, table, entities, entity_index, start)

_MoveDataOp(cols, _empty) = _MoveDataOp(cols)
_CopyDataToEndOp(cols, _empty) = _CopyDataToEndOp(cols)
_RemoveDataOp(cols, _empty) = _RemoveDataOp(cols)
_SwapDataOp(cols, _empty) = _SwapDataOp(cols)
_PermuteCycleOp(cols, _empty) = _PermuteCycleOp(cols)

struct _ErasedDispatch
    activate_column::Vector{_FW_ActivateColumn}
    ensure_column_size::Vector{_FW_EnsureColumnSize}
    move_data::Vector{_FW_MoveData}
    copy_data_ref::Vector{_FW_CopyData}
    copy_data_copy::Vector{_FW_CopyData}
    copy_data_deepcopy::Vector{_FW_CopyData}
    copy_data_to_end::Vector{_FW_CopyDataToEnd}
    clear_column::Vector{_FW_ClearColumn}
    remove_data::Vector{_FW_RemoveData}
    swap_data::Vector{_FW_SwapData}
    permute_cycle::Vector{_FW_PermuteCycle}
end

function _ErasedDispatch(n::Int)
    return _ErasedDispatch(
        Vector{_FW_ActivateColumn}(undef, n),
        Vector{_FW_EnsureColumnSize}(undef, n),
        Vector{_FW_MoveData}(undef, n),
        Vector{_FW_CopyData}(undef, n),
        Vector{_FW_CopyData}(undef, n),
        Vector{_FW_CopyData}(undef, n),
        Vector{_FW_CopyDataToEnd}(undef, n),
        Vector{_FW_ClearColumn}(undef, n),
        Vector{_FW_RemoveData}(undef, n),
        Vector{_FW_SwapData}(undef, n),
        Vector{_FW_PermuteCycle}(undef, n),
    )
end

@inline function _storage_at(storages::Memory{Any}, comp::Int)
    if comp < 1 || comp > length(storages)
        throw(ArgumentError(lazy"no component with id $comp in the World"))
    end
    return @inbounds storages[comp]
end

@generated function _storage_at(storages::CS, comp::Int) where {CS<:Tuple}
    call_exprs = Expr[:(storages[$i]) for i in 1:fieldcount(CS)]
    switch = _generate_component_switch(:comp, call_exprs)
    return quote
        $switch
        throw(ArgumentError(lazy"no component with id $comp in the World"))
    end
end

@noinline function _build_erased!(v::Vector{FW}, comp::Int, stores, op::F) where {FW<:FunctionWrapper,F}
    @inbounds v[comp] = FW(op(_storage_at(stores._storages, comp), _storage_at(stores._empty_storages, comp)))
    return nothing
end

@inline function _erased_activate_column(stores, comp::Int)
    v = stores._dispatch.activate_column
    isassigned(v, comp) || _build_erased!(v, comp, stores, _ActivateColumnOp)
    return @inbounds v[comp]
end

@inline function _erased_ensure_column_size(stores, comp::Int)
    v = stores._dispatch.ensure_column_size
    isassigned(v, comp) || _build_erased!(v, comp, stores, _EnsureColumnSizeOp)
    return @inbounds v[comp]
end

@inline function _erased_move_data(stores, comp::Int)
    v = stores._dispatch.move_data
    isassigned(v, comp) || _build_erased!(v, comp, stores, _MoveDataOp)
    return @inbounds v[comp]
end

_copy_data_op(mode::Val) = (cols, _empty) -> _CopyDataOp(cols, mode)

@inline function _erased_copy_data(stores, comp::Int, mode::Val{:ref})
    v = stores._dispatch.copy_data_ref
    isassigned(v, comp) || _build_erased!(v, comp, stores, _copy_data_op(mode))
    return @inbounds v[comp]
end

@inline function _erased_copy_data(stores, comp::Int, mode::Val{:copy})
    v = stores._dispatch.copy_data_copy
    isassigned(v, comp) || _build_erased!(v, comp, stores, _copy_data_op(mode))
    return @inbounds v[comp]
end

@inline function _erased_copy_data(stores, comp::Int, mode::Val{:deepcopy})
    v = stores._dispatch.copy_data_deepcopy
    isassigned(v, comp) || _build_erased!(v, comp, stores, _copy_data_op(mode))
    return @inbounds v[comp]
end

@inline function _erased_copy_data_to_end(stores, comp::Int)
    v = stores._dispatch.copy_data_to_end
    isassigned(v, comp) || _build_erased!(v, comp, stores, _CopyDataToEndOp)
    return @inbounds v[comp]
end

@inline function _erased_clear_column(stores, comp::Int)
    v = stores._dispatch.clear_column
    isassigned(v, comp) || _build_erased!(v, comp, stores, _ClearColumnOp)
    return @inbounds v[comp]
end

@inline function _erased_remove_data(stores, comp::Int)
    v = stores._dispatch.remove_data
    isassigned(v, comp) || _build_erased!(v, comp, stores, _RemoveDataOp)
    return @inbounds v[comp]
end

@inline function _erased_swap_data(stores, comp::Int)
    v = stores._dispatch.swap_data
    isassigned(v, comp) || _build_erased!(v, comp, stores, _SwapDataOp)
    return @inbounds v[comp]
end

@inline function _erased_permute_cycle(stores, comp::Int)
    v = stores._dispatch.permute_cycle
    isassigned(v, comp) || _build_erased!(v, comp, stores, _PermuteCycleOp)
    return @inbounds v[comp]
end


struct _UseMap end
struct _NoUseMap end

struct _NoGraphNode{M}
    mask::_NoMask{M}
end

_NoGraphNode{M}() where M = _NoGraphNode(_NoMask{M}())

# The graph stores its nodes in flat pools (`masks`, `archetypes`, `neighbors`)
# addressed by a 1-based `UInt32` node id, so that no node value is ever boxed.
# The `nodes` map associates each component mask with its node id and the
# `neighbors` array stores, per node, the ids of the adjacent nodes indexed by
# component id (`0` means no edge). Node `1` is always the root (empty mask).
mutable struct _Graph{M}
    const mask::_MutableMask{M}
    const nodes::_Linear_Map{_Mask{M},UInt32,true,true,NoZero,NoZero}
    const masks::Vector{_Mask{M}}
    const archetypes::Vector{UInt32}
    const neighbors::Vector{Vector{UInt32}}
    last_node::UInt32
    last_mask::_Mask{M}
end

function _Graph{M}() where M
    m = _Mask{M}()
    g = _Graph{M}(
        _MutableMask{M}(),
        _Linear_Map{_Mask{M},UInt32}(),
        _Mask{M}[m],
        UInt32[UInt32(1)],
        Vector{UInt32}[UInt32[]],
        UInt32(1),
        m,
    )
    g.nodes[m] = UInt32(1)
    return g
end

@inline function _get_neighbor(g::_Graph, node::UInt32, bit::Int)
    vec = @inbounds g.neighbors[Int(node)]
    (bit <= length(vec)) || return UInt32(0)
    @inbounds n = vec[bit]
    return n
end

function _set_neighbor!(g::_Graph, node::UInt32, bit::Int, neighbor::UInt32)
    vec = @inbounds g.neighbors[Int(node)]
    if length(vec) < bit
        old_len = length(vec)
        resize!(vec, (bit + _vec_map_chunk_size) & -_vec_map_chunk_size)
        fill!(@view(vec[(old_len + 1):end]), UInt32(0))
    end
    @inbounds vec[bit] = neighbor
    return nothing
end

function _find_or_create(g::_Graph, mask::_MutableMask)
    immut_mask = _Mask(mask)
    get!(() -> begin
        id = UInt32(length(g.masks) + 1)
        push!(g.masks, immut_mask)
        push!(g.archetypes, typemax(UInt32))
        push!(g.neighbors, UInt32[])
        id
    end, g.nodes, immut_mask)
end

@inline function _check_find_node(start_mask::_Mask, add_mask::_Mask, rem_mask::_Mask)
    if !_contains_all(start_mask, rem_mask)
        throw(ArgumentError("entity does not have component to remove"))
    elseif _contains_any(start_mask, add_mask)
        throw(ArgumentError("entity already has component to add"))
    end
end

@inline function _check_find_node(start_mask::_Mask, add_mask::_Mask, rem_mask::_NoMask)
    if _contains_any(start_mask, add_mask)
        throw(ArgumentError("entity already has component to add"))
    end
end

@inline function _check_find_node(start_mask::_Mask, add_mask::_NoMask, rem_mask::_Mask)
    if !_contains_all(start_mask, rem_mask)
        throw(ArgumentError("entity does not have component to remove"))
    end
end

@inline _check_find_node(start_mask::_NoMask, add_mask::_Mask, rem_mask::_NoMask) = nothing
@inline _check_find_node(start_mask::_NoMask, add_mask::_NoMask, rem_mask::_NoMask) = nothing
@inline _check_find_node(start_mask::_Mask, add_mask::_NoMask, rem_mask::_NoMask) = nothing

@inline _new_mask(start_mask::_Mask, add_mask::_Mask, rem_mask::_Mask) =
    _clear_bits(_or(add_mask, start_mask), rem_mask)
@inline _new_mask(start_mask::_Mask, add_mask::_Mask, rem_mask::_NoMask) = _or(add_mask, start_mask)
@inline _new_mask(start_mask::_Mask, add_mask::_NoMask, rem_mask::_Mask) = _clear_bits(start_mask, rem_mask)
@inline _new_mask(start_mask::_NoMask, add_mask::_Mask, rem_mask::_NoMask) = add_mask
@inline _new_mask(start_mask::_Mask, add_mask::_NoMask, rem_mask::_NoMask) = start_mask
@inline function _new_mask(start_mask::_NoMask{M}, add_mask::_NoMask{M}, rem_mask::_NoMask{M}) where M
    return _Mask{M}()
end

@inline _start_mask(g::_Graph{M}, start::UInt32) where M = @inbounds g.masks[Int(start)]
@inline _start_mask(g::_Graph{M}, start::_NoGraphNode{M}) where M = _Mask{M}()

@inline _path_start(g::_Graph, start::UInt32) = start
@inline _path_start(g::_Graph, start::_NoGraphNode) = UInt32(1)

function _find_node(g::_Graph{M}, start::Union{UInt32,_NoGraphNode{M}},
    start_mask::Union{_Mask{M},_NoMask{M}}, add::Tuple{Vararg{Int}},
    remove::Tuple{Vararg{Int}}, add_mask::Union{_Mask{M},_NoMask{M}}, rem_mask::Union{_Mask{M},_NoMask{M}},
    use_map::Union{_NoUseMap,_UseMap}) where M
    _check_find_node(start_mask, add_mask, rem_mask)
    _search_node(g, start, start_mask, add, remove, add_mask, rem_mask, use_map)
end

@inline function _search_node(g::_Graph{M}, start::Union{UInt32,_NoGraphNode{M}},
    start_mask::Union{_Mask{M},_NoMask{M}}, add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}},
    add_mask::Union{_Mask{M},_NoMask{M}}, rem_mask::Union{_Mask{M},_NoMask{M}}, use_map::_UseMap) where M
    new_mask = _new_mask(start_mask, add_mask, rem_mask)
    if new_mask.bits == g.last_mask.bits
        return g.last_node
    end
    node = get(() -> _find_or_create_path(g, start, start_mask, add, remove), g.nodes, new_mask)
    g.last_node = node
    g.last_mask = new_mask
    return node
end

@inline function _search_node(g::_Graph{M}, start::Union{UInt32,_NoGraphNode{M}},
    start_mask::Union{_Mask{M},_NoMask{M}}, add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}},
    add_mask::Union{_Mask{M},_NoMask{M}}, rem_mask::Union{_Mask{M},_NoMask{M}}, use_map::_NoUseMap) where M
    new_mask = _new_mask(start_mask, add_mask, rem_mask)
    if new_mask.bits == g.last_mask.bits
        return g.last_node
    end
    node = _find_or_create_path(g, start, start_mask, add, remove)
    g.last_node = node
    g.last_mask = new_mask
    return node
end

function _find_or_create_path(g, start, start_mask, add, remove)
    curr = _path_start(g, start)
    _set_mask!(g.mask, start_mask)
    for b in remove
        _clear_bit!(g.mask, b)

        next = _get_neighbor(g, curr, b)
        if next != UInt32(0)
            curr = next
        else
            node = _find_or_create(g, g.mask)
            _set_neighbor!(g, node, b, curr)
            _set_neighbor!(g, curr, b, node)
            curr = node
        end
    end
    for b in add
        _set_bit!(g.mask, b)

        next = _get_neighbor(g, curr, b)
        if next != UInt32(0)
            curr = next
        else
            node = _find_or_create(g, g.mask)
            _set_neighbor!(g, node, b, curr)
            _set_neighbor!(g, curr, b, node)
            curr = node
        end
    end

    return curr
end

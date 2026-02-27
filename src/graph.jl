
struct _UseMap end
struct _NoUseMap end

struct _GraphNode{M}
    mask::_Mask{M}
    neighbors::_VecMap{_GraphNode{M},M}
    archetype::Base.RefValue{UInt32}
end

function _GraphNode(mask::_Mask{M}, archetype::UInt32) where M
    _GraphNode{M}(mask, _VecMap{_GraphNode{M},M}(), Base.RefValue{UInt32}(archetype))
end

mutable struct _Graph{M}
    const mask::_MutableMask{M}
    const nodes::_Linear_Map{_Mask{M},_GraphNode{M}}
    last_node::_GraphNode{M}
end

function _Graph{M}() where M
    m = _Mask{M}()
    node = _GraphNode(m, UInt32(1))
    g = _Graph{M}(_MutableMask{M}(), _Linear_Map{_Mask{M},_GraphNode{M}}(), node)
    get!(() -> node, g.nodes, m)
    return g
end

function _find_or_create(g::_Graph, mask::_MutableMask)
    immut_mask = _Mask(mask)
    get!(() -> _GraphNode(immut_mask, typemax(UInt32)), g.nodes, immut_mask)
end

function _find_node(g::_Graph, start::_GraphNode, add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}},
    add_mask::_Mask, rem_mask::_Mask, use_map::Union{_NoUseMap,_UseMap})
    if !_contains_all(start.mask, rem_mask)
        throw(ArgumentError("entity does not have component to remove"))
    elseif _contains_any(start.mask, add_mask)
        throw(ArgumentError("entity already has component to add"))
    end
    _search_node(g, start, add, remove, add_mask, rem_mask, use_map)
end

@inline function _search_node(g::_Graph, start::_GraphNode, add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}},
    add_mask::_Mask, rem_mask::_Mask, use_map::_UseMap)
    new_mask = _clear_bits(_or(add_mask, start.mask), rem_mask)
    if new_mask.bits == g.last_node.mask.bits
        return g.last_node
    end
    node = get(() -> _find_or_create_path(g, start, add, remove), g.nodes, new_mask)
    g.last_node = node
    return node
end

@inline function _search_node(g::_Graph, start::_GraphNode, add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}},
    add_mask::_Mask, rem_mask::_Mask, use_map::_NoUseMap)
    new_mask = _clear_bits(_or(add_mask, start.mask), rem_mask)
    if new_mask.bits == g.last_node.mask.bits
        return g.last_node
    end
    node = _find_or_create_path(g, start, add, remove)
    g.last_node = node
    return node
end

function _find_or_create_path(g, start, add, remove)
    curr = start
    _set_mask!(g.mask, start.mask)
    for b in remove
        _clear_bit!(g.mask, b)

        if _get_bit(curr.neighbors.used, b)
            curr = curr.neighbors.data[b]
        else
            next = _find_or_create(g, g.mask)
            _set_map!(next.neighbors, b, curr)
            _set_map!(curr.neighbors, b, next)
            curr = next
        end
    end
    for b in add
        _set_bit!(g.mask, b)

        if _get_bit(curr.neighbors.used, b)
            curr = curr.neighbors.data[b]
        else
            next = _find_or_create(g, g.mask)
            _set_map!(next.neighbors, b, curr)
            _set_map!(curr.neighbors, b, next)
            curr = next
        end
    end

    return curr
end


struct _UseMap end
struct _NoUseMap end

struct _NoGraphNode{M}
    mask::_NoMask{M}
end

_NoGraphNode{M}() where M = _NoGraphNode(_NoMask{M}())

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
    const nodes::_Linear_Map{_Mask{M},_GraphNode{M},true,true,NoZero,NoZero}
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

@inline function _check_find_node(start::_GraphNode, add_mask::_Mask, rem_mask::_Mask)
    if !_contains_all(start.mask, rem_mask)
        throw(ArgumentError("entity does not have component to remove"))
    elseif _contains_any(start.mask, add_mask)
        throw(ArgumentError("entity already has component to add"))
    end
end

@inline function _check_find_node(start::_GraphNode, add_mask::_Mask, rem_mask::_NoMask)
    if _contains_any(start.mask, add_mask)
        throw(ArgumentError("entity already has component to add"))
    end
end

@inline function _check_find_node(start::_GraphNode, add_mask::_NoMask, rem_mask::_Mask)
    if !_contains_all(start.mask, rem_mask)
        throw(ArgumentError("entity does not have component to remove"))
    end
end

@inline _check_find_node(start::_NoGraphNode, add_mask::_Mask, rem_mask::_NoMask) = nothing
@inline _check_find_node(start::_NoGraphNode, add_mask::_NoMask, rem_mask::_NoMask) = nothing

@inline _new_mask(start::_GraphNode, add_mask::_Mask, rem_mask::_Mask) = _clear_bits(_or(add_mask, start.mask), rem_mask)
@inline _new_mask(start::_GraphNode, add_mask::_Mask, rem_mask::_NoMask) = _or(add_mask, start.mask)
@inline _new_mask(start::_GraphNode, add_mask::_NoMask, rem_mask::_Mask) = _clear_bits(start.mask, rem_mask)
@inline _new_mask(start::_NoGraphNode, add_mask::_Mask, rem_mask::_NoMask) = add_mask
@inline function _new_mask(start::_NoGraphNode{M}, add_mask::_NoMask{M}, rem_mask::_NoMask{M}) where M
    return _Mask{M}()
end

@inline _start_mask(start::_GraphNode) = start.mask
@inline _start_mask(start::_NoGraphNode{M}) where M = _Mask{M}()

@inline _path_start(g::_Graph, start::_GraphNode) = start
@inline function _path_start(g::_Graph{M}, start::_NoGraphNode{M}) where M
    return g.nodes[_Mask{M}()]
end

function _find_node(g::_Graph{M}, start::Union{_GraphNode{M},_NoGraphNode{M}}, add::Tuple{Vararg{Int}},
    remove::Tuple{Vararg{Int}}, add_mask::Union{_Mask{M},_NoMask{M}}, rem_mask::Union{_Mask{M},_NoMask{M}},
    use_map::Union{_NoUseMap,_UseMap}) where M
    _check_find_node(start, add_mask, rem_mask)
    _search_node(g, start, add, remove, add_mask, rem_mask, use_map)
end

@inline function _search_node(g::_Graph{M}, start::Union{_GraphNode{M},_NoGraphNode{M}},
    add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}}, add_mask::Union{_Mask{M},_NoMask{M}},
    rem_mask::Union{_Mask{M},_NoMask{M}}, use_map::_UseMap) where M
    new_mask = _new_mask(start, add_mask, rem_mask)
    if new_mask.bits == g.last_node.mask.bits
        return g.last_node
    end
    node = get(() -> _find_or_create_path(g, start, add, remove), g.nodes, new_mask)
    g.last_node = node
    return node
end

@inline function _search_node(g::_Graph{M}, start::Union{_GraphNode{M},_NoGraphNode{M}},
    add::Tuple{Vararg{Int}}, remove::Tuple{Vararg{Int}}, add_mask::Union{_Mask{M},_NoMask{M}},
    rem_mask::Union{_Mask{M},_NoMask{M}}, use_map::_NoUseMap) where M
    new_mask = _new_mask(start, add_mask, rem_mask)
    if new_mask.bits == g.last_node.mask.bits
        return g.last_node
    end
    node = _find_or_create_path(g, start, add, remove)
    g.last_node = node
    return node
end

function _find_or_create_path(g, start, add, remove)
    curr = _path_start(g, start)
    _set_mask!(g.mask, _start_mask(start))
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

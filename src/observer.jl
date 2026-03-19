
"""
    observe!(
        fn::Function,
        world::World,
        event::Event,
        components::Tuple=();
        with::Tuple=(),
        without::Tuple=(),
        exclusive::Bool=false,
        register::Bool=true,
    )

Creates an [Observer](@ref) and (optionally, default) registers it.

See [Event](@ref) for built-in, and [EventRegistry](@ref) for custom event types.

# Arguments

  - `fn::Function`: A callback function to execute when a matching event is received. Can be used via a `do` block.
  - `world::World`: The [World](@ref) to observe.
  - `event::Event`: The [Event](@ref) to observe.
  - `components::Tuple=()`: The component types to observe. Must be empty for `OnCreateEntity` and `OnRemoveEntity`.
  - `with::Tuple=()`: Components the entity must have.
  - `without::Tuple=()`: Components the entity must not have.
  - `exclusive::Bool=false`: Makes the observer exclusive for entities that have exactly the components given be `with`.
  - `register::Bool=true`: Whether the observer is registered immediately. Alternatively, register later with [observe!](@ref observe!(::World, ::Observer; ::Bool))

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
observe!(world, OnAddComponents, (Position, Velocity); with=(Altitude,)) do entity
    println(entity)
end

# output

Observer(:OnAddComponents, (Position, Velocity); with=(Altitude))
```
"""
Base.@constprop :aggressive function observe!(
    fn::Function,
    world::W,
    event::Event,
    components::Tuple=();
    with::Tuple=(),
    without::Tuple=(),
    exclusive::Bool=false,
    register::Bool=true,
) where {W<:World}
    _Observer_from_types(
        world, event,
        _ObserverCallback(fn),
        ntuple(i -> Val(components[i]), length(components)),
        ntuple(i -> Val(with[i]), length(with)),
        ntuple(i -> Val(without[i]), length(without)),
        Val(exclusive), register)
end

@generated function _Observer_from_types(
    world::W,
    event::Event,
    fn::_ObserverCallback,
    ::CT,
    ::WT,
    ::WO,
    ::EX,
    register::Bool,
) where {W<:World,CT<:Tuple,WT<:Tuple,WO<:Tuple,EX<:Val}
    comp_types = _to_types(CT)
    with_types = _to_types(WT)
    without_types = _to_types(WO)

    if EX === Val{true} && !isempty(without_types)
        throw(ArgumentError("cannot use 'exclusive' together with 'without'"))
    end

    CS = W.parameters[1]
    ids = map(C -> _component_id(CS, C), comp_types)
    with_ids = map(C -> _component_id(CS, C), with_types)
    without_ids = map(C -> _component_id(CS, C), without_types)

    all_comps_relations = true
    for T in comp_types
        if !(T <: Relationship)
            all_comps_relations = false
        end
    end

    M = max(1, cld(length(CS.parameters), 64))
    mask = _Mask{M}(ids...)
    with_mask = _Mask{M}(with_ids...)
    exclude_mask = EX === Val{true} ? _Mask{M}(_Not(), with_ids...) : _Mask{M}(without_ids...)

    has_comps_expr = (length(comp_types) > 0) ? :(true) : :(false)
    has_with_expr = (length(with_types) > 0) ? :(true) : :(false)
    has_without = (length(without_types) > 0) || (EX === Val{true})
    has_without_expr = has_without ? :(true) : :(false)
    is_exclusive = EX === Val{true} ? :(true) : :(false)

    return quote
        if (event == OnCreateEntity || event == OnRemoveEntity) && _is_not_zero($mask)
            throw(ArgumentError("components tuple must be empty for event types OnCreateEntity and OnRemoveEntity"))
        end
        if (event == OnAddRelations || event == OnRemoveRelations) && !$all_comps_relations
            throw(
                ArgumentError(
                    "all components must be relationships for event types OnAddRelations and OnRemoveRelations",
                ),
            )
        end
        obs = Observer(
            world,
            _ObserverID(UInt32(0)),
            event,
            $mask,
            $with_mask,
            $exclude_mask,
            $has_comps_expr,
            $has_with_expr,
            $has_without_expr,
            $is_exclusive,
            fn,
        )
        if register
            register!(obs)
        end
        obs
    end
end

"""
    register!(observer::Observer)

Registers the given [Observer](@ref).
Note that observers created with [observe!](@ref) are automatically registered by default.
"""
function register!(observer::Observer)
    _add_observer!(observer._world._event_manager, observer)
end

"""
    unregister!(observer::Observer)

Un-registers the given [Observer](@ref).
"""
function unregister!(observer::Observer)
    _remove_observer!(observer._world._event_manager, observer)
end

function Base.show(io::IO, obs::Observer{W}) where {W<:_AbstractWorld}
    world_types = W.parameters[2].parameters

    mask_ids = _active_bit_indices(obs._comps)
    mask_types = tuple(map(i -> world_types[Int(i)].parameters[1], mask_ids)...)
    with_ids = _active_bit_indices(obs._with)
    with_types = tuple(map(i -> world_types[Int(i)].parameters[1], with_ids)...)

    mask_names = join(map(_format_type, mask_types), ", ")
    with_names = join(map(_format_type, with_types), ", ")

    excl_types = ()
    without_names = ""
    if !obs._is_exclusive
        excl_ids = _active_bit_indices(obs._without)
        excl_types = tuple(map(i -> world_types[Int(i)].parameters[1], excl_ids)...)
        without_names = join(map(_format_type, excl_types), ", ")
    end

    kw_parts = String[]
    if !isempty(with_types)
        push!(kw_parts, "with=($with_names)")
    end
    if !isempty(excl_types)
        push!(kw_parts, "without=($without_names)")
    end
    if obs._is_exclusive
        push!(kw_parts, "exclusive=true")
    end

    if isempty(kw_parts)
        print(io, "Observer(:$(obs._event._symbol), ($mask_names))")
    else
        print(io, "Observer(:$(obs._event._symbol), ($mask_names); ", join(kw_parts, ", "), ")")
    end
end

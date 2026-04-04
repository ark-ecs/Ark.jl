
"""
    Event

Type for built-in and custom events.
See [EventRegistry](@ref) for creating custom event types.

# Built-in event types

  - `OnCreateEntity`: Event emitted after a new entity is created.
  - `OnRemoveEntity`: Event emitted before an entity is removed from the [World](@ref).
  - `OnAddComponents`: Event emitted after components are added to an entity.
  - `OnRemoveComponents`: Event emitted before components are removed from an entity.
  - `OnAddRelations`: Event emitted after relation targets are added to an entity.
    Includes creating entities, adding components as well as setting relation targets.
  - `OnRemoveRelations`: Event emitted before relation targets are removed from an entity.
    Includes removing entities, removing components as well as setting relation targets.
"""
struct Event
    _id::Int
    _symbol::Symbol

    Event(id::Int, symbol::Symbol) = new(id, symbol)
end

function Base.show(io::IO, evt::Event)
    print(io, "Event(:$(evt._symbol))")
end

const OnCreateEntity::Event = Event(1, :OnCreateEntity)
const OnRemoveEntity::Event = Event(2, :OnRemoveEntity)
const OnAddComponents::Event = Event(3, :OnAddComponents)
const OnRemoveComponents::Event = Event(4, :OnRemoveComponents)
const OnAddRelations::Event = Event(5, :OnAddRelations)
const OnRemoveRelations::Event = Event(6, :OnRemoveRelations)

const _EVENT_MANAGER_INITIAL_CAPACITY = 6

"""
    EventRegistry

Serves for creating custom event types.
"""
mutable struct EventRegistry
    _event_types::Dict{Symbol,Int}
end

"""
    EventRegistry()

Creates a new [EventRegistry](@ref).
"""
function EventRegistry()
    reg = EventRegistry(Dict{Symbol,Int}())
    new_event_type!(reg, :OnCreateEntity)
    new_event_type!(reg, :OnRemoveEntity)
    new_event_type!(reg, :OnAddComponents)
    new_event_type!(reg, :OnRemoveComponents)
    new_event_type!(reg, :OnAddRelations)
    new_event_type!(reg, :OnRemoveRelations)
    reg
end

function Base.show(io::IO, reg::EventRegistry)
    symbols = map(x -> ":$(x[1])", (sort(collect(reg._event_types), by=x -> x[2])))

    print(io, "$(length(reg._event_types))-events EventRegistry()")
    print(io, "\n [$(join(symbols, ", "))]\n")
end

"""
    new_event_type!(reg::EventRegistry, symbol::Symbol)

Creates a new custom [Event](@ref).
Custom event types are best stored in global constants.

The symbol is only used for printing.

# Example

```jldoctest; setup = :(using Ark; include(string(dirname(pathof(Ark)), "/docs.jl"))), output = false
registry = EventRegistry()
const OnGameOver = new_event_type!(registry, :OnGameOver)

# output

Event(:OnGameOver)
```
"""
function new_event_type!(reg::EventRegistry, symbol::Symbol)
    if haskey(reg._event_types, symbol)
        throw(ArgumentError("there is already an event with symbol :$symbol"))
    end
    id = length(reg._event_types) + 1
    reg._event_types[symbol] = id
    return Event(id, symbol)
end

mutable struct _ObserverID
    id::UInt32
end

"""
    Observer

Observer for reacting on built-in and custom events.

See [observe!](@ref) for details.
See [Event](@ref) for built-in, and [EventRegistry](@ref) for custom event types.
"""
struct Observer{W<:_AbstractWorld,M}
    _world::W
    _id::_ObserverID
    _event::Event
    _comps::_Mask{M}
    _with::_Mask{M}
    _without::_Mask{M}
    _has_comps::Bool
    _has_with::Bool
    _has_without::Bool
    _is_exclusive::Bool
    _fn::FunctionWrapper{Nothing,Tuple{Entity}}
end

mutable struct _EventManager{W<:_AbstractWorld,M}
    const observers::Vector{Vector{Observer{W,M}}}
    const comps::Vector{Tuple{_Mask{M},Bool}}
    const with::Vector{Tuple{_Mask{M},Bool}}
    num_observers::Int
    max_event_type::Int
end

function _EventManager{W,M}() where {W<:_AbstractWorld,M}
    len = _EVENT_MANAGER_INITIAL_CAPACITY
    _EventManager{W,M}(
        [Vector{Observer{W,M}}() for _ in 1:len],
        [(_Mask{M}(), false) for _ in 1:len],
        [(_Mask{M}(), false) for _ in 1:len],
        0, 0,
    )
end

function _ensure_capacity!(m::_EventManager{W,M}, id::Int) where {W<:_AbstractWorld,M}
    cap = length(m.observers)
    if id <= cap
        return
    end

    resize!(m.observers, id)
    @inbounds for i in (cap+1):id
        m.observers[i] = Vector{Observer{W,M}}()
    end

    resize!(m.comps, id)
    @inbounds for i in (cap+1):id
        m.comps[i] = (_Mask{M}(), false)
    end

    resize!(m.with, id)
    @inbounds for i in (cap+1):id
        m.with[i] = (_Mask{M}(), false)
    end
end

@inline function _has_observers(m::_EventManager, event::Event)
    return m.num_observers > 0 &&
           event._id <= length(m.observers) &&
           !isempty(@inbounds m.observers[id])
end

function _add_observer!(m::_EventManager, o::Observer)
    if o._id.id > 0
        throw(InvalidStateException("observer is already registered", :observer_already_registered))
    end
    m.num_observers += 1

    e = o._event._id
    _ensure_capacity!(m, e)
    push!(m.observers[e], o)
    o._id.id = UInt32(length(m.observers[e]))

    if e > m.max_event_type
        m.max_event_type = e
    end

    with, any_no_with = m.with[e]
    if o._has_with
        with = _or(with, o._with)
    else
        any_no_with = true
    end
    m.with[e] = (with, any_no_with)

    if o._event == OnCreateEntity || o._event == OnRemoveEntity
        return
    end

    comps, any_no_comps = m.comps[e]
    if o._has_comps
        comps = _or(comps, o._comps)
    else
        any_no_comps = true
    end
    m.comps[e] = (comps, any_no_comps)
end

function _remove_observer!(m::_EventManager{W,M}, o::Observer{W,M}) where {W<:_AbstractWorld,M}
    if o._id.id == 0
        throw(InvalidStateException("observer is not registered", :observer_not_registered))
    end
    m.num_observers -= 1

    e = o._event._id
    observers = m.observers[e]
    swapped = _swap_remove!(observers, o._id.id)
    if swapped
        observers[o._id.id]._id.id = o._id.id
    end
    o._id.id = 0

    # rebuild mask unions

    with_mask = _Mask{M}()
    any_no_with = false
    for o in m.observers[e]
        if !o._has_with
            any_no_with = true
            break # skip, as the unions mask is irrelevant
        end
        with_mask = _or(with_mask, o._with)
    end
    m.with[e] = (with_mask, any_no_with)

    if o._event == OnCreateEntity || o._event == OnRemoveEntity
        return
    end

    comps_mask = _Mask{M}()
    any_no_comps = false
    for o in m.observers[e]
        if !o._has_comps
            any_no_comps = true
            break # skip, as the unions mask is irrelevant
        end
        comps_mask = _or(comps_mask, o._comps)
    end
    m.comps[e] = (comps_mask, any_no_comps)
end

function _reset!(m::_EventManager{W,M}) where {W<:_AbstractWorld,M}
    for e in 1:m.max_event_type
        if length(m.observers[e]) == 0
            continue
        end
        for obs in m.observers[e]
            obs._id.id = 0
        end
        empty!(m.observers[e])
        m.comps[e] = (_Mask{M}(), false)
        m.with[e] = (_Mask{M}(), false)
    end

    m.max_event_type = 0
    m.num_observers = 0
end

function _fire_create_entity(m::_EventManager{W,M}, entity::Entity, mask::_Mask{M}) where {W<:_AbstractWorld,M}
    _do_fire_no_comps(m, OnCreateEntity, entity, mask, true)
end

function _fire_remove_entity(m::_EventManager{W,M}, entity::Entity, mask::_Mask{M}) where {W<:_AbstractWorld,M}
    _do_fire_no_comps(m, OnRemoveEntity, entity, mask, true)
end

function _fire_create_entity_relations(
    m::_EventManager{W,M},
    entity::Entity,
    mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    _do_fire_comps(m, OnAddRelations, entity, mask, mask, true)
end

function _fire_remove_entity_relations(
    m::_EventManager{W,M},
    entity::Entity,
    mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    _do_fire_comps(m, OnRemoveRelations, entity, mask, mask, true)
end

function _fire_create_entities(m::_EventManager{W,M}, table::_BatchTable{M}) where {W<:_AbstractWorld,M}
    evt = OnCreateEntity._id
    observers = m.observers[evt]
    mask = table.archetype.node.mask
    if length(observers) > 1
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, mask)
            return
        end
    end
    for o in observers
        if o._has_with && !_contains_all(mask, o._with)
            continue
        end
        if o._has_without && _contains_any(mask, o._without)
            continue
        end
        entities = table.table.entities._data
        for i in table.start_idx:table.end_idx
            o._fn(entities[i])
        end
    end
end

function _fire_create_entities_relations(m::_EventManager{W,M}, table::_BatchTable{M}) where {W<:_AbstractWorld,M}
    _do_fire_comps(m, OnAddRelations, table, table.archetype.node.mask)
end

function _fire_remove_entities(
    m::_EventManager{W,M},
    table::_Table,
    mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    evt = OnRemoveEntity._id
    observers = m.observers[evt]
    if length(observers) > 1
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, mask)
            return
        end
    end
    for o in observers
        if o._has_with && !_contains_all(mask, o._with)
            continue
        end
        if o._has_without && _contains_any(mask, o._without)
            continue
        end
        for entity in table.entities
            o._fn(entity)
        end
    end
end

function _fire_remove_entities_relations(
    m::_EventManager{W,M},
    table::_Table,
    mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    evt = OnRemoveRelations._id
    observers = m.observers[evt]
    if length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps && !_contains_any(comps, mask)
            return
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, mask)
            return
        end
    end
    for o in observers
        if o._has_comps && !_contains_all(mask, o._comps)
            continue
        end
        if o._has_with && !_contains_all(mask, o._with)
            continue
        end
        if o._has_without && _contains_any(mask, o._without)
            continue
        end
        for entity in table.entities
            o._fn(entity)
        end
    end
end

function _fire_add(
    m::_EventManager{W,M},
    event::Event,
    entity::Entity,
    old_mask::_Mask{M},
    new_mask::_Mask{M},
    early_out::Bool,
)::Bool where {W<:_AbstractWorld,M}
    evt = event._id
    observers = m.observers[evt]
    if early_out && length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps &&
           (!_contains_any(comps, new_mask) || _contains_all(old_mask, comps))
            return false
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, old_mask)
            return false
        end
    end
    found = false
    for o in observers
        if o._has_comps && (!_contains_all(new_mask, o._comps) || _contains_any(old_mask, o._comps))
            continue
        end
        if o._has_with && !_contains_all(old_mask, o._with)
            continue
        end
        if o._has_without && _contains_any(old_mask, o._without)
            continue
        end
        o._fn(entity)
        found = true
    end
    return found
end

function _fire_add(
    m::_EventManager{W,M},
    event::Event,
    table::_BatchTable,
    old_mask::_Mask{M},
    new_mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    evt = event._id
    observers = m.observers[evt]
    if length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps &&
           (!_contains_any(comps, new_mask) || _contains_all(old_mask, comps))
            return
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, old_mask)
            return
        end
    end
    for o in observers
        if o._has_comps && (!_contains_all(new_mask, o._comps) || _contains_any(old_mask, o._comps))
            continue
        end
        if o._has_with && !_contains_all(old_mask, o._with)
            continue
        end
        if o._has_without && _contains_any(old_mask, o._without)
            continue
        end
        entities = table.table.entities._data
        for i in table.start_idx:table.end_idx
            o._fn(entities[i])
        end
    end
    return nothing
end

function _fire_remove(
    m::_EventManager{W,M},
    event::Event,
    entity::Entity,
    old_mask::_Mask{M},
    new_mask::_Mask{M},
    early_out::Bool,
)::Bool where {W<:_AbstractWorld,M}
    evt = event._id
    observers = m.observers[evt]
    if early_out && length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps &&
           (!_contains_any(comps, old_mask) || _contains_all(new_mask, comps))
            return false
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, old_mask)
            return false
        end
    end
    found = false
    for o in observers
        if o._has_comps && (!_contains_all(old_mask, o._comps) || _contains_any(new_mask, o._comps))
            continue
        end
        if o._has_with && !_contains_all(old_mask, o._with)
            continue
        end
        if o._has_without && _contains_any(old_mask, o._without)
            continue
        end
        o._fn(entity)
        found = true
    end
    return found
end

function _fire_remove(
    m::_EventManager{W,M},
    event::Event,
    table::_BatchTable,
    old_mask::_Mask{M},
    new_mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    evt = event._id
    observers = m.observers[evt]
    if length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps &&
           (!_contains_any(comps, old_mask) || _contains_all(new_mask, comps))
            return
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, old_mask)
            return
        end
    end
    for o in observers
        if o._has_comps && (!_contains_all(old_mask, o._comps) || _contains_any(new_mask, o._comps))
            continue
        end
        if o._has_with && !_contains_all(old_mask, o._with)
            continue
        end
        if o._has_without && _contains_any(old_mask, o._without)
            continue
        end
        entities = table.table.entities._data
        for i in table.start_idx:table.end_idx
            o._fn(entities[i])
        end
    end
    return nothing
end

function _fire_set_relations(
    m::_EventManager{W,M},
    event::Event,
    entity::Entity,
    mask::_MutableMask{M},
    entity_mask::_Mask{M},
    early_out::Bool,
) where {W<:_AbstractWorld,M}
    _do_fire_comps(m, event, entity, mask, entity_mask, early_out)
end

function _fire_set_relations(
    m::_EventManager{W,M},
    event::Event,
    table::_BatchTable{M},
    mask::_MutableMask{M},
) where {W<:_AbstractWorld,M}
    _do_fire_comps(m, event, table, mask)
end

function _fire_custom_event(
    m::_EventManager{W,M},
    event::Event,
    entity::Entity,
    mask::_Mask{M},
    entity_mask::_Mask{M},
) where {W<:_AbstractWorld,M}
    _do_fire_comps(m, event, entity, mask, entity_mask, true)
end

@inline function _do_fire_comps(
    m::_EventManager{W,M},
    event::Event,
    entity::Entity,
    mask::MK,
    entity_mask::_Mask{M},
    early_out::Bool,
) where {W<:_AbstractWorld,MK<:_AbstractMask{M}} where {M}
    evt = event._id
    observers = m.observers[evt]
    if early_out && length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps && !_contains_any(comps, mask)
            return false
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, entity_mask)
            return false
        end
    end
    found = false
    for o in observers
        if o._has_comps && !_contains_all(mask, o._comps)
            continue
        end
        if o._has_with && !_contains_all(entity_mask, o._with)
            continue
        end
        if o._has_without && _contains_any(entity_mask, o._without)
            continue
        end
        o._fn(entity)
        found = true
    end
    return found
end

@inline function _do_fire_comps(
    m::_EventManager{W,M},
    event::Event,
    table::_BatchTable{M},
    mask::MK,
) where {W<:_AbstractWorld,MK<:_AbstractMask{M}} where {M}
    evt = event._id
    observers = m.observers[evt]
    entity_mask = table.archetype.node.mask
    if length(observers) > 1
        comps, any_no_comps = m.comps[evt]
        if !any_no_comps && !_contains_any(comps, mask)
            return
        end
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, entity_mask)
            return
        end
    end
    for o in observers
        if o._has_comps && !_contains_all(mask, o._comps)
            continue
        end
        if o._has_with && !_contains_all(entity_mask, o._with)
            continue
        end
        if o._has_without && _contains_any(entity_mask, o._without)
            continue
        end
        entities = table.table.entities._data
        for i in table.start_idx:table.end_idx
            o._fn(entities[i])
        end
    end
end

@inline function _do_fire_no_comps(
    m::_EventManager{W,M},
    event::Event,
    entity::Entity,
    mask::_Mask{M},
    early_out::Bool,
) where {W<:_AbstractWorld,M}
    evt = event._id
    observers = m.observers[evt]
    if early_out && length(observers) > 1
        with, any_no_with = m.with[evt]
        if !any_no_with && !_contains_any(with, mask)
            return false
        end
    end
    found = false
    for o in observers
        if o._has_with && !_contains_all(mask, o._with)
            continue
        end
        if o._has_without && _contains_any(mask, o._without)
            continue
        end
        o._fn(entity)
        found = true
    end
    return found
end

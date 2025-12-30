module Ark

using FieldViews
using Preferences
using StaticArrays
using FunctionWrappers: FunctionWrapper

isdefined(@__MODULE__, :Memory) || const Memory = Vector # Compat for Julia < 1.11

const IS_TEST_ENV = @load_preference("IS_TEST_ENV", default = "false")

include("abstract.jl")
include("util.jl")
include("collections.jl")
include("structarray.jl")
include("fieldsview.jl")
include("entity.jl")
include("mask.jl")
include("vec_map.jl")
include("storage.jl")
include("linear_map.jl")
include("graph.jl")
include("table.jl")
include("archetype.jl")
include("cache.jl")
include("event.jl")
include("index.jl")
include("registry.jl")
include("pool.jl")
include("lock.jl")
include("world.jl")
include("observer.jl")
include("filter.jl")
include("query.jl")
include("batch_ops.jl")
# this is necessary since coverage is wrongly
# reported with a precompilation workload
IS_TEST_ENV != "true" && include("precompile.jl")

#include("docs.jl") # doctest setup

export World
export is_alive, new_entity!, new_entities!, copy_entity!
export remove_entity!, remove_entities!, zero_entity, is_locked, reset!
export get_components, set_components!, has_components
export add_components!, remove_components!
export exchange_components!
export get_relations, set_relations!
export get_resource, has_resource, add_resource!, set_resource!, remove_resource!

export Entity
export is_zero

export Query, Filter
export close!, count_entities, unregister!

export Entities

export EventType, EventRegistry, new_event_type!
export OnCreateEntity, OnRemoveEntity, OnAddComponents, OnRemoveComponents
export OnAddRelations, OnRemoveRelations

export Observer, observe!, emit_event!
export unpack, @unpack

export StructArrayStorage, VectorStorage, Relationship

end


Base.@propagate_inbounds @inline function _unchecked_getindex(collection, indices...)
    return Base.getindex(collection, indices...)
end

Base.@propagate_inbounds @inline function _unchecked_setindex!(collection, value, indices...)
    return Base.setindex!(collection, value, indices...)
end

@inline function _unchecked_in(item, collection)
    return Base.in(item, collection)
end

function _add_unchecked!(expr)
    mod = :Ark

    fn_uncheck = (
        :has_components, :get_components, :set_components!, :add_components!,
        :remove_components!, :exchange_components!, :get_relations, :set_relations!,
        :remove_entity!, :copy_entity!,
    )
    fn_uncheck_base = (
        getindex = :(Ark._unchecked_getindex),
        setindex! = :(Ark._unchecked_setindex!),
        in = :(Ark._unchecked_in),
    )

    exprs = [expr]
    while !isempty(exprs)
        ex = pop!(exprs)

        if ex.head === :ref
            ex.head = :call
            insert!(ex.args, 1, fn_uncheck_base.getindex)
        elseif ex.head === :(=) && ex.args[1] isa Expr && ex.args[1].head === :ref
            ref_ex = ex.args[1]
            ex.head = :call
            ex.args = [
                fn_uncheck_base.setindex!, 
                ref_ex.args[1],
                ex.args[2],
                ref_ex.args[2:end]...
            ]
        elseif ex.head == :call
            fn = ex.args[1]
            is_fn = fn isa Symbol && fn in fn_uncheck
            is_fn_mod = fn isa Expr && fn.head == :. && fn.args[1] == mod && fn.args[2].value in fn_uncheck
            if is_fn || is_fn_mod
                idx = findfirst(a -> a isa Expr && a.head === :parameters, ex.args)
                if idx === nothing
                    insert!(ex.args, 2, Expr(:parameters, Expr(:kw, :_unchecked, true)))
                else
                    params = ex.args[idx]
                    has_unchecked = any(p -> (p isa Expr && p.head === :kw && p.args[1] === :_unchecked), params.args)
                    if !has_unchecked
                        push!(params.args, Expr(:kw, :_unchecked, true))
                    end
                end
            end

            is_fn = fn isa Symbol && fn in keys(fn_uncheck_base)
            is_fn_base = fn isa Expr && fn.head == :. && fn.args[1] == :Base && fn.args[2].value in keys(fn_uncheck_base)
            if is_fn
                ex.args[1] = fn_uncheck_base[ex.args[1]]
            elseif is_fn_base
                ex.args[1] = fn_uncheck_base[fn.args[2].value]
            end
        end
        for a in ex.args
            if a isa Expr
                pushfirst!(exprs, a)
            end
        end
    end

    return expr
end

"""
    @unchecked block

Removes some checks performed by these functions and their shortcuts:
`has_components`, `get_components`, `set_components!`, `add_components!`,
`remove_components!`, `exchange_components!`, `get_relations`, `set_relations!`,
`remove_entity!`, `copy_entity!`.

In particular, checks about the aliveness of the entity and presence of components
on which the functions operate are skipped.

!!! warning

    Using `@unchecked` may return incorrect results/crashes/corruption when the checks
    would throw if enabled. The user is responsible for evaluating that the checks
    are avoidable. It must be certain from the information locally available that
    they can be skipped.
"""
macro unchecked(block)
    return esc(_add_unchecked!(block))
end

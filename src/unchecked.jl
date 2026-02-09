
function _add_unchecked!(expr)
    mod = :Ark
    fn_uncheck = (
        :has_components, :get_components, :set_components!, :add_components!,
        :remove_components!, :exchange_components!, :get_relations, :set_relations!,
        :remove_entity!, :copy_entity!,
    )

    exprs = [expr]
    while !isempty(exprs)
        ex = pop!(exprs)
        if ex.head == :call
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

Removes some checks performed by these functions: `has_components`, `get_components`,
`set_components!`, `add_components!`, `remove_components!`, `exchange_components!`,
`get_relations`, `set_relations!`, `remove_entity!`, `copy_entity!`.

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

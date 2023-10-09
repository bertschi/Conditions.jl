module Conditions

using Infiltrator

# Simple non-local exit

struct NonLocal{T}
    tag::Symbol
    val::T
end

function nonlocal(body, tag)
    try
        body()
    catch e
        if isa(e, NonLocal) && e.tag == tag
            e.val
        else
            rethrow(e)
        end
    end
end

function jump(tag, val)
    throw(NonLocal(tag, val))
end

# Dynamically bound handlers

struct Handler{T,F}
    type::T
    fun::F
end

const handler_key = gensym("handler_stack")

function get_handlers()
    store = task_local_storage()
    if haskey(store, handler_key)
        store[handler_key]
    else
        nothing
    end
end

function with_handlers(body, stack)
    task_local_storage(body, handler_key, stack)
end

# Handler stack is stored as nested pairs used like a nothing terminated list!
struct NoMatchingHandler{C} <: Exception
    condition::C
end

handle_interactive::Ref{Bool} = Ref(true)

toggle_interactive(b::Bool) = handle_interactive[] = b

function signal(condition)
    # Just run all matching handlers here
    stack = get_handlers()
    while !isnothing(stack)
        with_handlers(last(stack)) do
            for handler in first(stack)
                if condition isa handler.type
                    handler.fun(condition)
                end
            end
        end
        stack = last(stack)
    end
end

# Make signal a macro to @infiltrate at actual error location in interactive use
macro signal(condition)
    c = esc(condition)
    quote
        signal($c)
        # Now check for interactive use or throw
        if handle_interactive[]
            @infiltrate
        else
            throw(NoMatchingHandler($c))
        end
    end
end

function handler_bind(body, handlers...)
    with_handlers(body, handlers => get_handlers())
end

export nonlocal, jump

export Handler, NoMatchingHandler
export toggle_interactive, @signal, handler_bind

end # module Conditions

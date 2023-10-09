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

const default_handler = Handler(Exception, c -> @infiltrate)

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
    # Check for default handler
    if condition isa default_handler.type
        with_handlers(nothing) do
            default_handler.fun(condition)
        end
    else
        throw(NoMatchingHandler(condition))
    end
end

function handler_bind(body, handlers...)
    with_handlers(body, handlers => get_handlers())
end

export nonlocal, jump

export Handler, NoMatchingHandler
export signal, handler_bind

end # module Conditions

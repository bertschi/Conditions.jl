# Conditions.jl

Common Lisp like condition system for Julia

Start with the docstring of `@handler_case` to see how this works ...
```julia-repl
help?> @handler_case
  Convenience macro around handler_bind which works similar to try-catch, i.e., the first matching handler is run with the stack unwound and its result is returned.

  Examples
  ≡≡≡≡≡≡≡≡≡≡

  julia> @handler_case @signal(3.0) begin
             Integer => c -> (:integer, c)
             Number => c -> (:number, c)
             Any => c -> (:any, c)
         end
  (:number, 3.0)

  See also @signal, handler_bind as well as nonlocal and jump.
```

**Features**

* `@signal` does not unwind the stack, i.e., in contrast to `throw`

* Restarts allow to continue execution higher up in the stack

  TODO: Implement restarts!

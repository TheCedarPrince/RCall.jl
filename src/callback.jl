"""
Register a function pointer as an R NativeSymbol. We technically are supposed to use
R_registerRoutines. Starting from R 3.4, `R_MakeExternalPtrFn` is a part of R API in R 3.4.
It is probably safe to such to make the external pointer.
"""
function makeNativeSymbolRef(fptr::Ptr{Void})
    # mirror Rf_MakeNativeSymbolRef of Rdynload.c
    rexfn = ccall((:R_MakeExternalPtrFn,libR), Ptr{ExtPtrSxp},
                     (Ptr{Void}, Ptr{Void}, Ptr{Void}),
                     fptr, sexp(Symbol("native symbol")), sexp(Const.NilValue))
    setattrib!(rexfn, Const.ClassSymbol, sexp("NativeSymbol"))
    preserve(rexfn)
    rexfn
end


"Create an Ptr{ExtPtrSxp} object"
makeExternalPtr(ptr::Ptr{Void}, tag=Const.NilValue, prot=Const.NilValue) =
    ccall((:R_MakeExternalPtr,libR), Ptr{ExtPtrSxp},
          (Ptr{Void}, Ptr{UnknownSxp}, Ptr{UnknownSxp}),
          ptr, sexp(tag), sexp(prot))


"""
The function called by R .External for Julia callbacks.

It receives a `Ptr{ListSxp}` containing
 - a pointer to the function itself (`Ptr{ExtPtrSxp}`)
 - a pointer to the Julia function (`Ptr{ExtPtrSxp}`)
 - any arguments (as `Ptr{S<:Sxp}`)
"""
function julia_extptr_callback(p::Ptr{ListSxp})
    try
        l = cdr(p) # skip callback pointer

        # julia function pointer
        f_sxp = car(l)::Ptr{ExtPtrSxp}
        f_sxprec = unsafe_load(f_sxp)
        f = unsafe_pointer_to_objref(f_sxprec.ptr)
        l = cdr(l)

        # # extract arguments
        args = Any[]
        kwargs = Any[]
        for (k,a) in l
            # TODO: provide a mechanism for users to specify their own
            # conversion routines
            if k == sexp(Const.NilValue)
                push!(args,rcopy(a))
            else
                push!(kwargs,(rcopy(Symbol,k),rcopy(a)))
            end
        end

        # call function
        y = f(args...;kwargs...)

        # return appropriate sexp
        return p = convert(Ptr{UnknownSxp},sexp(y))::Ptr{UnknownSxp}
    catch e
        ccall((:Rf_error,libR),Ptr{Void},(Ptr{Cchar},),string(e))
        return convert(Ptr{UnknownSxp},sexp(Const.NilValue))::Ptr{UnknownSxp}
    end
end


"""
Julia types (typically functions) which are wrapped in `Ptr{ExtPtrSxp}` are
stored here to prevent garbage collection by Julia.
"""
const jtypExtPtrs = Dict{Ptr{ExtPtrSxp}, Any}()

"""
Called by the R finalizer.
"""
function decref_extptr(p::Ptr{ExtPtrSxp})
    delete!(jtypExtPtrs, p)
    return nothing
end


"""
Register finalizer to be called by the R GC.
"""
function registerCFinalizerEx(s::Ptr{ExtPtrSxp})
    protect(s)
    decref_extptr_ptr = cfunction(decref_extptr,Void,(Ptr{ExtPtrSxp},))
    ccall((:R_RegisterCFinalizerEx,libR),Void,
          (Ptr{ExtPtrSxp}, Ptr{Void}, Cint),
          s,decref_extptr_ptr,0)
    unprotect(1)
end


const juliaCallback = RObject{ExtPtrSxp}()


function setup_callbacks()
    julia_extptr_callback_ptr = cfunction(julia_extptr_callback,Ptr{UnknownSxp},(Ptr{ListSxp},))
    juliaCallback.p = makeNativeSymbolRef(julia_extptr_callback_ptr)
end


"""
Wrap a Julia object an a R `Ptr{ExtPtrSxp}`.

We store the pointer and the object in a const Dict to prevent it being
removed by the Julia GC.
"""
function sexp(::Type{ExtPtrSxp}, j)
    jptr = pointer_from_objref(j)
    s = makeExternalPtr(jptr)
    jtypExtPtrs[s] = j
    registerCFinalizerEx(s)
    s
end

"""
Wrap a callable Julia object `f` an a R `ClosSxpPtr`.

Constructs the following R code

    function(...) .External(juliaCallback, fExPtr, ...)

"""
function sexp(::Type{ClosSxp}, f)
    fptr = protect(sexp(ExtPtrSxp,f))
    body = protect(rlang_p(Symbol(".External"),
                           juliaCallback,
                           fptr,
                           Const.DotsSymbol))
    local clos
    try
        lang = rlang_p(:function, sexp_arglist_dots(), body)
        clos = reval_p(lang)
    finally
        unprotect(2)
    end
    clos
end


"""
Create an argument list for an R function call, with a varargs "dots" at the end.
"""
function sexp_arglist_dots(args...;kwargs...)
    rarglist = protect(allocList(length(args)+length(kwargs)+1))
    try
        rr = rarglist
        for var in args
            settag!(rr, sexp(var))
            setcar!(rr, Const.MissingArg)
            rr = cdr(rr)
        end
        for (var,val) in kwargs
            settag!(rr, sexp(var))
            setcar!(rr, sexp(val))
            rr = cdr(rr)
        end
        settag!(rr, Const.DotsSymbol)
        setcar!(rr, Const.MissingArg)
    finally
        unprotect(1)
    end
    rarglist
end

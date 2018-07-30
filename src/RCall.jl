__precompile__()
module RCall

using Compat
using Dates
using Libdl
using Random
using REPL
using Missings
using Nullables
using CategoricalArrays
using DataFrames
using AxisArrays
import StatsModels: Formula, parse!
import DataStructures: OrderedDict
import Nullables: isnull

import Base: eltype, convert, isascii,
    names, length, size, getindex, setindex!, iterate,
    show, showerror, write
import Base.Iterators: Enumerate

export RObject,
   Sxp, NilSxp, StrSxp, CharSxp, LglSxp, IntSxp, RealSxp, CplxSxp,
   ListSxp, VecSxp, EnvSxp, LangSxp, ClosSxp, S4Sxp,
   getattrib, setattrib!, getnames, setnames!, getclass, setclass!, attributes,
   globalEnv,
   isna, anyna,
   rcopy, rparse, rprint, reval, rcall, rlang,
   rimport, @rimport, @rlibrary, @rput, @rget, @var_str, @R_str

const depfile = joinpath(dirname(@__FILE__),"..","deps","deps.jl")
if isfile(depfile)
    include(depfile)
else
    error("RCall not properly installed. Please run Pkg.build(\"RCall\")")
end

include("setup.jl")
include("types.jl")
include("Const.jl")
include("methods.jl")
include("convert/base.jl")
include("convert/missing.jl")
include("convert/categorical.jl")
include("convert/datetime.jl")
include("convert/dataframe.jl")
include("convert/formula.jl")
include("convert/nullable.jl")
include("convert/axisarray.jl")
include("convert/default.jl")
include("eventloop.jl")
include("eval.jl")
include("language.jl")
include("io.jl")
include("callback.jl")
include("namespaces.jl")
include("render.jl")
include("macros.jl")
include("operators.jl")
include("RPrompt.jl")
include("ijulia.jl")
include("deprecated.jl")

end # module

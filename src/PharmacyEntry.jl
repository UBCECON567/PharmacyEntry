module PharmacyEntry

using DataFrames, HTTP, Gumbo, Cascadia, CSV, PyCall, LightXML,
  Statistics, PlotlyJS, Distributions
import ArchGDAL, Geodesy

export
  loadpharmacydata,
  loadcensusdata,
  loaddistancematrix,
  geocode!,
  plotmap,
  checklatlng!,
  brentrysim,
  distance_m,
  logfinite

include("geo.jl")
include("pharmacies.jl")
include("census.jl")
include("entrymodel.jl")

"""
     logfinite(cut)

  Returns log(x) if x>=cut, first order taylor
  expansion of log(x) around cut if x<cut. 


  Main purpose is to avoid returning -Inf while maximizing a log
  likelihood.  
"""
function logfinite(cut::Number)
  lc = log(cut)
  dlc =1.0/cut
  function(x)
    if (x>=cut)
      log(x)
    else
      lc + (x-cut)*dlc
    end
  end
end


end # module PharmacyEntry

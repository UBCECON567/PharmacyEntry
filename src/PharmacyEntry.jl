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
  distance_m

include("geo.jl")
include("pharmacies.jl")
include("census.jl")
include("entrymodel.jl")


end # module PharmacyEntry

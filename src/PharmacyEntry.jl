module PharmacyEntry

using DataFrames, HTTP, Gumbo, Cascadia, CSV, PyCall, LightXML,
  Statistics, PlotlyJS
import ArchGDAL, Geodesy

export
  loadpharmacydata,
  loadcensusdata,
  loaddistancematrix,
  geocode!,
  plotmap,
  checklatlng!

include("geo.jl")
include("pharmacies.jl")
include("census.jl")


end # module PharmacyEntry

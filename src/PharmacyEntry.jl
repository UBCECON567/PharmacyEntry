module PharmacyEntry

using DataFrames, HTTP, Gumbo, Cascadia, CSV, PyCall, LightXML, Statistics
import ArchGDAL, Geodesy

export
  loadpharmacydata,
  loadcensusdata,
  loaddistancematrix,
  geocode!

include("geo.jl")
include("pharmacies.jl")
include("census.jl")


end # module PharmacyEntry

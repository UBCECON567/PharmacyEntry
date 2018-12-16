module PharmacyEntry

using DataFrames, HTTP, Gumbo, Cascadia, CSV, PyCall, LightXML

export
  loadpharmacydata,
  loadcensusdata,
  loaddistancematrix

include("pharmacies.jl")

include("census.jl")

include("distancematrix.jl")

#function loadcensusdata()
#  println("hello!?")
#end
         

end # module PharmacyEntry

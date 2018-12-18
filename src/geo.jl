# Function related to geography. Looking up lat/lon, distances, and so
# on.

"""
     geocode!(df::AbstractDataFrame,address::Symbol)

Geocodes addresses contained in `df[address]`. Adds latitutde in
df[:lat], longitude in df[:lng], and accuracy in df[:llaccuracy]

Uses geocod.io for geocoding. Requires a geocod.io API key and the
pygeocodio Python module. 
"""
function geocode!(df::AbstractDataFrame,
                  address::Symbol)
  if !isfile("geocodio.key")
    error("geocodio.key not found")
  end
  keyfile = open("geocodio.key","r") 
  key = read(keyfile, String);
  close(keyfile)  
  geocodio = pyimport("geocodio")  
  client = geocodio[:GeocodioClient](key)
  tmp = zeros(3,nrow(df))
  blocksize = 100
  function extractlatlonacc(loc)
    try
      [collect(values(loc["results"][1]["location"]))...
       loc["results"][1]["accuracy"]]
    catch
      [0; 0; -1]
    end
  end
  for b in 1:blocksize:nrow(df)
    s = b
    e = min(b+blocksize-1, nrow(df))
    @info "requesting geocode for addresses $s : $e"
    locations = client[:geocode](df[address][s:e])
    tmp[:,s:e] = hcat(extractlatlonacc.(locations)...)
  end
  df[:llaccuracy] = tmp[3,:]
  if (any(df[:llaccuracy].<0))
    df[:lat] = Array{Union{Missing, eltype(tmp)},1}(undef, nrow(df))
    df[:lng] = Array{Union{Missing, eltype(tmp)},1}(undef, nrow(df))
  else 
    df[:lat] = Array{eltype(tmp),1}(undef, nrow(df))
    df[:lng] = Array{eltype(tmp),1}(undef, nrow(df))
  end
    
  df[:lat] .= tmp[1,:]
  df[:lng] .= tmp[2,:]
  df[:lat][df[:llaccuracy].<0] .= missing
  df[:lng][df[:llaccuracy].<0] .= missing
  df
end

## construct geographic markets using map data from google
# We use the Python client for Google map services, see
#  https://github.com/googlemaps/google-maps-services-python
# You will need an API key for this, see google's docs for info.
#
# 
function loaddistancematrix(;redownload=false)
  csvfile=normpath(joinpath(@__DIR__,"..","data","distancematrix.csv"))
  if (redownload || !isfile(csvfile))
    # create googlemaps client
    googlemaps = pyimport("googlemaps") # you must install googlemaps, e.g.  `$ pip install -U googlemaps`
    if (!isflie("googleDistanceMatrix.key"))
      error("\"googleDistanceMatrix.key\" file not found. Obtain a".*
            " Google DistanceMatrix API and save it in a text file".*
            " with this name.")
    end
    keyfile = open("googleDistanceMatrix.key")
    gkey = read(keyfile, String);
    close(keyfile)
    gmaps = googlemaps.Client(key = gkey)

    # create well formatted addresses for each pharmacy    
    function addressstring(df)
      df[:street].*", ".*df[:city].*", ".*df[:province].*", ".*df[:zip]
    end
    pharm[:address] = addressstring(pharm)

  
    provinceabbr = Dict("Newfoundland and Labrador" => "NL",
                        "Prince Edward Island" => "PE",
                        "Nova Scotia" => "NS",
                        "New Brunswick" => "NB",
                        "Quebec" => "QC",
                        "Ontario" => "ON",
                        "Manitoba" => "MB",
                        "Saskatchewan" => "SK",
                        "Alberta" => "AB",
                        "British Columbia" => "BC",
                        "Yukon" => "YT",
                        "Northwest Territories" => "NT",
                        "Nunavut" => "NU")
    abbrprovince = Dict()
    for key in keys(provinceabbr)
      abbrprovince[provinceabbr[key]] = key
    end
    # look up distances separately for each province to limit requests
    for pv in unique(pharm[:province])
      ph = pharm[pharm[:province].==pv,:]

      # some population centres are on borders and have
      # province1/province2 for PROV_TERR_NAME_NOM
      pcensus = census[occursin.(abbrprovince[pv], 
                                 census[:PROV_TERR_NAME_NOM]), :]
      pcensus[:address] = (pcensus[:GEO_NAME].*", " .*pv)

      #distances = gmaps[:distance_matrix](origins = ph[:address][1:2],
      #                                    destinations = pcensus[:address][1:3],
      #                                    mode = "driving",
      #                                    units = "metric",
      #                                   region = "ca")
    end
  end
  
end

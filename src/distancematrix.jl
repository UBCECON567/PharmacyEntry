## construct geographic markets using map data from google
# We use the Python client for Google map services, see
#  https://github.com/googlemaps/google-maps-services-python
# You will need an API key for this, see google's docs for info.
#
# 
function loaddistancematrix()
  googlemaps = pyimport("googlemaps") # you must install googlemaps, e.g.  `$ pip install -U googlemaps`
  keyfile = open("googleDistanceMatrix.key")
  gkey = read(keyfile, String);
  close(keyfile)
  gmaps = googlemaps.Client(key = gkey)
  function addressstring(df)
    df[:street].*", ".*df[:city].*", ".*df[:province].*", ".*df[:zip]
  end
  mb[:address] = addressstring(mb)
  census[:address] = (census[:GEO_NAME].*", " .*
                      # some population centres are on borders,
                      # these have province1/province2 listed for province.
                      # we remove the /province2 so distance_matrix doesn't get confused
                      (a->replace(a,r"(.+)(/.+)" => s"\1")).(census[:PROV_TERR_NAME_NOM]) )
  censusmb = census[census[:PROV_TERR_NAME_NOM].=="Manitoba",:]
  distances = gmaps[:distance_matrix](origins = mb[:address][1:2],
                                      destinations = censusmb[:address][1:3],
                                      mode = "driving",
                                      units = "metric",
                                      region = "ca")
end

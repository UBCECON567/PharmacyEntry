# Functions related to geography. Looking up lat/lon, distances, and so
# on.


################################################################################
#
# I gave up on using google maps for this project. It seems like
# storing query results would violate Google's TOS. Also, getting the
# distance matrix for all 1000 pharmacies by 1000 populations =
# 1,000,000 queries = $5,000! Of course many of these queries could be
# avoided by e.g. only doing ones within X straightline distance, but
# it'll still cost around $25 and violate the TOS.
#
################################################################################


"""
     geocode!(df::AbstractDataFrame,address::Symbol)

Geocodes addresses contained in `df[address]`. Adds latitutde in
df[:lat], longitude in df[:lng], and accuracy in df[:llaccuracy]

Uses geocod.io for geocoding. Requires a geocod.io API key and the
pygeocodio Python module.
"""
function geocode!(df::AbstractDataFrame,
                  address::Symbol)
  keyfilename=normpath(joinpath(@__DIR__,"..","src","geocodio.key"))
  if !isfile(keyfilename)
    error("geocodio.key not found")
  end
  keyfile = open(keyfilename,"r")
  key = read(keyfile, String);
  close(keyfile)
  try 
    geocodio = pyimport("geocodio")
  catch err
    @info "First attempt to import python module geocodio failed, attempting to install."
    @info "If this still fails, it may work after restarting your Julia kernel."
    run(`pip install --user pygeocodio`)
    geocodio = pyimport("geocodio")    
  end
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



"""
     plotmap(census, pharm)

Plots map of census population centers and pharmacies.
"""
function plotmap(census, pharm)

  trace = scattergeo(;locationmode="ISO-3",
                     lat=census[:lat],
                     lon=census[:lng],
                     hoverinfo="text",
                     text=[string(x[:GEO_NAME], " pop: ", x[Symbol("Population, 2016")]) for x in eachrow(census)],
                     marker_size=log.(census[Symbol("Population, 2016")]),
                     marker_line_color="black", marker_line_width=2)
  idx  = pharm[:zipmatch]
  tp1 = scattergeo(;lat=pharm[:lat][idx], lon=pharm[:lng][idx],
                  marker_size = 10,
                  marker_color="green")
  tp2 = scattergeo(;lat=pharm[:lat][.!idx], lon=pharm[:lng][.!idx],
                   marker_size = 10,
                   hoverinfo="text",
                   text=[string(x[:address], " zip: ",
                                x[:zip])
                         for x in eachrow(pharm[.!idx,:])],
                   marker_color="red")
  nzp = pharm[.!pharm[:zipmatch],:]
  tozipctr = Array{typeof(trace)}(undef,nrow(nzp))
  for r in 1:nrow(nzp)
    tozipctr[r] = scattergeo(;lat=[nzp[:lat][r], nzp[:ziplat][r]],
                             lon= [nzp[:lng][r], nzp[:ziplng][r]],
                             mode = "lines",
                             hoverinfo = "none",
                             line_color="black")
  end

  geo = attr(scope="north america",
             resolution = 50,
             #projection_type="albers usa",
             showland=true,
             showrivers=true,
             showlakes=true,
             rivercolor="#fff",
             lakecolor="#fff",
             landcolor= "#EAEAAE",
             countrycolor= "#d3d3d3",
             countrywidth= 1.5,
             subunitcolor= "#d3d3d3",
             subunitwidth=1)
  traces = [trace,tp1,tp2, tozipctr...]
  println(typeof(traces))
  println(length(traces))
  layout = Layout(;title="Canada population centres and pharmacies", showlegend=false, geo=geo)
  plot(traces, layout)
end


"""
    checklatlng(df::AbstractDataFrame,
                lat::Symbol,
                lng::Symbol,
                zip::Symbol)

Checks latitude and longitude in df[:lat] and df[:lng] against zip
code in df[:zip].

Output:
  - Adds new variables to `df`
      - `:zipmatch::Bool` which is `true` if `df[:lat], df[:lng] ∈`
        Forward sortation area of `df[:zip]`
      - `:ziplat` and `:ziplng` latitude and longitude of centroid of
        forward soration area of `df[:zip]`

"""
function checklatlng!(df::AbstractDataFrame,
                     lat::Symbol,
                     lng::Symbol,
                     zip::Symbol)
  # statcan shapefile
  shpzip =
    normpath(joinpath(@__DIR__,"..","data","lfsa000b16a_e.zip"))
  if !isfile(shpzip)
    download("http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers/2016/lfsa000b16a_e.zip",
             shpzip)
  end
  shpfile = normpath(joinpath(@__DIR__,"..","data","lfsa000b16a_e.shp"))
  if !isfile(shpfile)
    unzippath = normpath(joinpath(@__DIR__,"..","data"))
    # the next command will likely fail on windows, use some  other
    # unzip progra
    run(`unzip $shpzip -d $unzippath`)
  end
  df[:zipmatch] = false
  df[:ziplat] = 0.0
  df[:ziplng] = 0.0
  df[:fsa] = (x->replace(x,r"(\p{L}\d\p{L}).?(\d\p{L}\d)" =>
                         s"\1")).(df[zip])

  ArchGDAL.registerdrivers() do
    ArchGDAL.read(shpfile) do sf
      layer = ArchGDAL.getlayer(sf, 0)
      nlayer = ArchGDAL.nfeature(layer)
      for i in 0:(nlayer-1)
        ArchGDAL.getfeature(layer, i) do feature
          fsa = ArchGDAL.getfield(feature, 0)
          m = findall(fsa.==df[:fsa])
          if (length(m)>0)
            geom = ArchGDAL.getgeomfield(feature,0)
            ArchGDAL.importEPSG(3347) do source
              ArchGDAL.importEPSG(4326) do target
                ArchGDAL.createcoordtrans(source, target) do transform
                  ArchGDAL.transform!(geom, transform)
                end
              end
            end
            cent = ArchGDAL.centroid(geom)
            cent=ArchGDAL.toWKT(cent)
            # convert string to Array{Float64,1}
            cent = parse.(Float64,split(replace(cent, r"POINT |\)|\("
                                                => "")," "))
            df[:ziplng][m] .= cent[1]
            df[:ziplat][m] .= cent[2]
            for j in m
              if ismissing(df[lng][j])
                df[:zipmatch][j] = false
              else
                phgeom = ArchGDAL.createpoint(df[lng][j], df[lat][j])
                df[:zipmatch][j] = ArchGDAL.intersects(geom, phgeom) # contains?
              end
            end # for j
          end # if length(m)>0
        end # do feature
      end # for i in 0:nlayer-1
    end # do sf
  end # do registerdrivers()

  df
end

"""
    distance_m(lng, lat, zlng, zlat)

Calculates the distance between the longitude and latitude
pairs. Returns missing if any of the inputs ismissing.
"""
function distance_m(lng, lat, zlng, zlat)
  if ismissing(lng) || ismissing(lat) || ismissing(zlng) || ismissing(zlat)
    missing
  else
    Geodesy.distance(Geodesy.LLA(lng, lat), Geodesy.LLA(zlng,zlat))
  end
end
#pharm[:zipdist] = distance_m(pharm[:lng],pharm[:lat], pharm[:ziplng],
#                             pharm[:ziplat])

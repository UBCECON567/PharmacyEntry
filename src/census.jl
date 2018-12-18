# Census variables to keep 
const vars = ["Population, 2016" 
              "Population, 2011"
              "Population density per square kilometre"
              "Land area in square kilometres"
              "0 to 14 years"
              "15 to 64 years"
              "65 years and over"
              "Average total income in 2015 among recipients (\$)"
              "Median total income in 2015 among recipients (\$)"
              "Median after-tax income in 2015 among recipients (\$)"
              "Number of government transfers recipients aged 15 years and over in private households - 100% data"
              "Median government transfers in 2015 among recipients (\$)"
              "Average government transfers in 2015 among recipients (\$)"
              "Prevalence of low income based on the Low-income measure, after tax (LIM-AT) (%)"
              "Total - Highest certificate, diploma or degree for the population aged 15 years and over in private households - 25% sample data"
              "No certificate, diploma or degree"
              "Secondary (high) school diploma or equivalency certificate"  
              "Postsecondary certificate, diploma or degree"      
              "Apprenticeship or trades certificate or diploma"   
              "Trades certificate or diploma other than Certificate of Apprenticeship or Certificate of Qualification"
              "Certificate of Apprenticeship or Certificate of Qualification"                                       
              "College, CEGEP or other non-university certificate or diploma"                                      
              "University certificate or diploma below bachelor level"                                             
              "University certificate, diploma or degree at bachelor level or above"                               
              "Bachelor's degree"                                                                                  
              "University certificate or diploma above bachelor level"                                             
              "Degree in medicine, dentistry, veterinary medicine or optometry"                                    
              "Master's degree"                                                                                    
              "Earned doctorate"                                                                                   
              "Total - Highest certificate, diploma or degree for the population aged 25 to 64 years in private households - 25% sample data"
              "Total - Major field of study - Classification of Instructional Programs (CIP) 2016 for the population aged 15 years and over in private households - 25% sample data"
              "Health and related fields"
              "Participation rate"                      
              "Employment rate"                                                       
              "Unemployment rate"
              "All occupations"                             
              "3 Health occupations"
              "Total - Commuting duration for the employed labour force aged 15 years and over in private households with a usual place of work or no fixed workplace address - 25% sample data"   
              "Less than 15 minutes"                                           
              "15 to 29 minutes"                                               
              "30 to 44 minutes"                                               
              "45 to 59 minutes"                                               
              "60 minutes and over"                                            
              ];

# dictionary for province abbreviations
const provinceabbr = Dict("Newfoundland and Labrador" => "NL",
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

"""
    loadcensusdata(;redownload=false, reparse=false) 
 
(Down)loads list of pharmacies in various Canadian provinces. 

Optional arguments:
  - `redownload` if true, will redownload source files, else tries to
     load from data directory
  - `reparse` if true will reparse downloaded files, else loads
     dataframe from csv

Output:
  - DataFrame of census population centres in canada

"""
function loadcensusdata(;redownload=false, reparse=false, regeocode=false)

  censuscsv =
    normpath(joinpath(@__DIR__,"..","data","popcentres.csv"))
  if (redownload || reparse || !isfile(censuscsv))
    rawcensusfile =
      normpath(joinpath(@__DIR__,"..","data","98-401-X2016048_English_CSV_data.csv"))
    zipfile = normpath(joinpath(@__DIR__,"..","data","census2016.csv.zip"))
    if (redownload || !isfile(zipfile))
      @info "Downloading raw census data from statcan"
      download("https://www12.statcan.gc.ca/census-recensement/2016/dp-pd/prof/details/download-telecharger/comp/GetFile.cfm?Lang=E&TYPE=CSV&GEONO=048",
               zipfile)
    end
    if (reparse || !isfile(rawcensusfile))
      unzippath = normpath(joinpath(@__DIR__,"..","data"))
      # the next command will likely fail on windows, use some  other
      # unzip progra
      run(`unzip $zipfile -d $unzippath`) 
    end
    
    if (reparse || !isfile(censuscsv))
      @info "Parsing raw census data"
      df = DataFrame(CSV.File(rawcensusfile))
      names!(df, [:CENSUS_YEAR                                             
                  :GEO_CODE
                  :GEO_LEVEL                                               
                  :GEO_NAME                                                
                  :GNR                                                     
                  :GNR_LF                                                  
                  :DATA_QUALITY_FLAG                                       
                  :ALT_GEO_CODE                                            
                  :name
                  :id
                  :Notes
                  :Total
                  :Male
                  :Female])
      # Census data is in "long" format, we only keep some variables, and
      # then reshape to wide
      
      newdf = df[df[:name] .∈ [vars],[:GEO_CODE, :GEO_NAME, :name, :Total]]
      wdf = unstack(newdf, :name, :Total)
      #
      # For some baffling reason StatsCan doesn't include province identifiers in the Population Centres file
      # StatsCan own documents say,
      # It is recommended that the two-digit province/territory (PR) 
      # code precede the POPCTR code in order to identify each POPCTR
      # uniquely within its 
      # corresponding province/territory.
      # https://www12.statcan.gc.ca/census-recensement/2016/ref/dict/geo049a-eng.cfm
      # Yet they don't follow this recommendation. 
      # At least they provide a semi-reasonable way to get this info
      #
      @info "Loading missing province codes from statcan"
      r = HTTP.get("https://www12.statcan.gc.ca/rest/census-recensement/CR2016Geo.xml?geos=POPCNTR")
      xdoc = parse_string(String(r.body));
      xroot = root(xdoc);  
      colnames = [attribute(XMLElement(c),"NAME")
                  for c in child_nodes(xroot["COLUMNNAMES"][1])]
      geocodes = DataFrame(Array{String, 2}(undef, 0, length(colnames)), Symbol.(colnames))
      for r in child_nodes(xroot["ROWS"][1])
        row = content.(collect(child_nodes(r)))
        push!(geocodes, row)
      end
      free(xdoc)
      wdf[:GEO_ID_CODE] = lpad.(wdf[:GEO_CODE],4,"0")
      census = join(wdf, geocodes, on = :GEO_ID_CODE)
      CSV.write(censuscsv,census)
    end
  else
    @info "reading cleaned census data from $censuscsv"
    census=CSV.read(censuscsv)
  end
  if (regeocode || !(:lat ∈ names(census)))
    # statcan shapefile   
    shpzip =
      normpath(joinpath(@__DIR__,"..","data","lpc_000b16a_e.zip"))
    if !isfile(shpzip)
      download("http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers/2016/lpc_000b16a_e.zip",
               shpzip)
    end
    shpfile = normpath(joinpath(@__DIR__,"..","data","lpc_000b16a_e.shp"))
    if !isfile(shpfile)
      unzippath = normpath(joinpath(@__DIR__,"..","data"))
      # the next command will likely fail on windows, use some  other
      # unzip progra
      run(`unzip $shpzip -d $unzippath`) 
    end
    
    pccentroids=ArchGDAL.registerdrivers() do
      ArchGDAL.read(shpfile) do sf
        layer = ArchGDAL.getlayer(sf, 0)
        println(layer)
        println("---------------------------")
        nlayer = ArchGDAL.nfeature(layer)
        println(nlayer)
        centroids = DataFrame([Array{String,1}(undef, 0),
                               Array{Float64,1}(undef, 0),
                               Array{Float64,1}(undef, 0)] ,
                              [:GEO_ID_CODE, :lng, :lat])
        for i in 0:(nlayer-1)
          ArchGDAL.getfeature(layer, i) do feature            
            id = ArchGDAL.getfield(feature, 0)
            geom = ArchGDAL.getgeomfield(feature,0)            
            cent = ArchGDAL.centroid(geom)
            ArchGDAL.importEPSG(3347) do source
              ArchGDAL.importEPSG(4326) do target
                ArchGDAL.createcoordtrans(source, target) do transform
                  ArchGDAL.transform!(cent, transform)
                end
              end
            end
            cent=ArchGDAL.toWKT(cent)
            # convert string to Array{Float64,1}
            cent = parse.(Float64,split(replace(cent, r"POINT |\)|\(" => "")," "))            
            push!(centroids, [id, cent...])
          end
        end
        centroids
      end      
    end
    pccentroids[:GEO_ID_CODE] = parse.(Int64,
                                       pccentroids[:GEO_ID_CODE])
    sort!(pccentroids, :GEO_ID_CODE)
    dupcodes=pccentroids[ pccentroids[:GEO_ID_CODE] .==
                          vcat(0, pccentroids[:GEO_ID_CODE][1:(nrow(pccentroids)-1)]),:][:GEO_ID_CODE] 
    # pop centres on borders appear twice in shapefile, replace with
    # mean centroid
    for c in dupcodes
      thisc = findall(pccentroids[:GEO_ID_CODE].==c)
      pccentroids[thisc,:lat] .= mean(pccentroids[thisc,:lat])
      pccentroids[thisc,:lng] .= mean(pccentroids[thisc,:lng])
      deleterows!(pccentroids, thisc[2:length(thisc)])
    end
    census = join(census, pccentroids, on = :GEO_ID_CODE)
    CSV.write(censuscsv, census)
  end
  census
end # function



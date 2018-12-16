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
function loadcensusdata(;redownload=false, reparse=false)

  rawcensusfile =
    normpath(joinpath(@__DIR__,"..","data","98-401-X2016048_English_CSV_data.csv"))
  censuscsv =
    normpath(joinpath(@__DIR__,"..","data","popcentres.csv"))
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
    
    # variables to keep
    vars = ["Population, 2016" 
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
            ]
    
    newdf = df[df[:name] .∈ [vars],[:GEO_CODE, :GEO_NAME, :name, :Total]]
    wdf = unstack(newdf, :name, :Total)

    #=
    For some baffling reason StatsCan doesn't include province identifiers in the Population Centres file ...
    StatsCan own documents say,
    "It is recommended that the two-digit province/territory (PR) code precede the POPCTR code in order to
    identify each POPCTR uniquely within its corresponding province/territory."
    https://www12.statcan.gc.ca/census-recensement/2016/ref/dict/geo049a-eng.cfm
    Yet they don't follow this recommendation. 
    At least they provide a semi-reasonable way to get this info
    =#
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
  else
    @info "reading cleaned census data from $censuscsv"
    census=CSV.read(censuscsv)
  end
  census
end # function

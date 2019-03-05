"""
    loadpharmacydata(;redownload=false, regeocode=false) 
 
(Down)loads list of pharmacies in various Canadian provinces. 

Optional arguments:
  - `redownload` if true, will redownload source files, else tries to
     load from data directory
  - `regeocode` if true, will recreate geocodes, else loads from data
     directory 

Output:
  - DataFrame listing pharmacies and their addresses

"""
function loadpharmacydata(;redownload=false, regeocode=false)
  csvfile=normpath(joinpath(@__DIR__,"..","data","pharmacies.csv"))
  if (redownload || !isfile(csvfile))
    bc = loadBCdata(redownload)
    mb = loadMBdata(redownload)
    nb = loadNBdata(redownload) 
    nl = loadNLdata(redownload)
    pe = loadPEdata(redownload)
    ## Additional province data can be found from links at
    ## https://www.pharmacists.ca/pharmacy-in-canada/directory-of-pharmacy-organizations/provincial-regulatory-authorities1/
    
    df = vcat(bc, mb, nb, nl, pe)     
    df[:id] = 1:nrow(df)    
    CSV.write(csvfile, df)
  else     
    println("reading pharmacy data from $csvfile")
    df = CSV.read(csvfile)
  end
  
  if (regeocode || !(:lat ∈ names(df)))
    df[:address_original] = df[:address]
    ## Look up latitude and longitude of each pharmacy    
    df[:address] =  (df[:street].*", ".*df[:city] .* ", " .*
                     df[:province] .* "  " .* df[:zip] .* ", Canada") 
    geocode!(df, :address)
    CSV.write(csvfile, df)
  end
  df
end


"""
     loadBCdata(redownload=false)

Load or download data on BC pharmacies

Inputs:
- `redownload`: whether to redownload data even if csv file exists.
Output: 
- Dataframe containing information on pharmacies
"""
function loadBCdata(redownload=false)
  csvfile=normpath(joinpath(@__DIR__,"..","data","bc-pharmacies.csv"))
  if (redownload || !isfile(csvfile))
    r = HTTP.get("http://www.bcpharmacists.org/list-community-pharmacies");
    h = parsehtml(String(r.body));
    
    rows = eachmatch(Selector("tr.odd, tr.even"), h.root);
    function parserow(row)
      fields = nodeText.(row.children)
      fields = reshape(fields, (1, length(fields)))
    end
    txt = vcat(parserow.(rows)...)
    bc = DataFrame(txt, [:name, :address, :manager, :phone, :fax])
    bc[:street] = (a->replace(a, r"(.+)\n.+, BC.+\n.+"s => s"\1")).(bc[:address])
    bc[:city] = (a->replace(a, r".+\n(.+), BC.+\n.+"s => s"\1")).(bc[:address])
    bc[:zip]  = (a->replace(a,r".+(\p{L}\d\p{L}).?(\d\p{L}\d).*"s => s"\1 \2")).(bc[:address])
    bc[:province] = "BC"
    CSV.write(csvfile, bc)    
  else
    bc = CSV.read(csvfile)
  end
  return(bc)
end


"""
     loadMBdata(redownload=false)

Load or download data on MB pharmacies

Inputs:
- `redownload`: whether to redownload data even if csv file exists.
Output: 
- Dataframe containing information on pharmacies
"""
function loadMBdata(redownload=false)
  csvfile=normpath(joinpath(@__DIR__,"..","data","mb-pharmacies.csv"))
  if (redownload || !isfile(csvfile))  
    r = HTTP.get("https://mpha.in1touch.org/company/roster/companyRosterView.html?companyRosterId=20");
    h = parsehtml(String(r.body));
    
    rows = eachmatch(Selector("div > div > table > tbody"),h.root);
    println(size(rows))
    rows = rows[2:length(rows)]; # first one is empty
    function parserowMB(row)
      name = nodeText(row.children[1])
      tmp = nodeText.(row.children[2].children[1].children)
      street = tmp[1]
      address = tmp[3]
      manager = tmp[7]
      tmp = nodeText.(row.children[2].children[2].children)
      phone = tmp[2]
      fax = tmp[7]
      txt = [name address manager phone fax street]
    end
    mb = DataFrame(vcat(parserowMB.(rows)...),
                   [:name, :address, :manager,:phone, :fax, :street])
    mb[:province] = "MB"
    mb[:city] = (a->replace(a, r"(^.+), M.+" => s"\1")).(mb[:address])
    mb[:zip]  = (a->replace(a,r".+(\p{L}\d\p{L}).?(\d\p{L}\d).*"s => s"\1 \2")).(mb[:address])
    CSV.write(csvfile,mb)
  else
    mb = CSV.read(csvfile)
  end
  return(mb)
end

"""

     loadNBdata(redownload=false)

Load or download data on NB pharmacies - modifies functions for Manitoba and BC given above

As above:
Inputs:
- `redownload`: whether to redownload data even if csv file exists.
Output: 
- Dataframe containing information on pharmacies
"""
function loadNBdata(redownload=false)
  # Contributors: Senna Eswaralingam, Matthew O'Brien, Yingxiang Li, & Jiancong Liu
  csvfile=normpath(joinpath(@__DIR__,"..","data","nb-pharmacies.csv"))
    
  if (redownload || !isfile(csvfile))  
    nb = 1 #to create a variable  that allows the fucntion below to be append contact from each scraped webpage to existing data
    for i = 1:5 #including this as New Brunswick's pharmacy contacts span 5 separate pages.
      web = string("https://www.nbpharmacists.ca/client/roster/clientRosterView.html?clientRosterId=208&page=", i)
      r =  HTTP.get(web) ;
      
      h = parsehtml(String(r.body));
      
      rows = eachmatch(Selector("div > div > table > tbody"),h.root);
      println(size(rows))
      rows = rows[2:length(rows)]; # first one is empty
      function parserowNB(row)
        name = nodeText(row.children[1].children[1].children[1].children[1].children[1])
        manager = nodeText(row.children[1].children[1].children[2].children[2])
        phone = nodeText(row.children[1].children[2].children[4].children[2])
        fax = nodeText(row.children[1].children[2].children[4].children[5])
        street = nodeText(row.children[1].children[2].children[2])
        city_prov_zip = nodeText(row.children[1].children[2].children[3])
        address = string(street, city_prov_zip)
        txt = [name manager phone fax street city_prov_zip address]
      end
      
      n = DataFrame(vcat(parserowNB.(rows)...),
                    [:name, :manager, :phone, :fax, :street, :city_prov_zip, :address])
      n[:city]   = (a->replace(a, r"(.+) NB .+"s => s"\1")).(n[:city_prov_zip])
      n[:zip]  =     (a->replace(a,r".+ NB (.+)" => s"\1")).(n[:city_prov_zip])
      n[:province] = "NB" 
      deletecols!(n, :city_prov_zip) #to align dataframe with manitoba and bc tables
      #Code to append scraped data from the latest iteration to the dataframe    
      if nb == 1
        nb = n
      else
        nb = vcat(nb,n)
      end      
    end  # for i
        
    CSV.write(csvfile,nb)
          
  else
    nb = CSV.read(csvfile)
  end # if redownload
  return(nb)
end


"""
Load or download data on NL pharmacies 

As above:
Inputs:
- `redownload`: whether to redownload data even if csv file exists.
Output: 
- Dataframe containing information on pharmacies
"""
function loadNLdata(redownload=false)
  # Contributors: Matthew O'Brien, Deepak Punjabi
  csvfile=normpath(joinpath(@__DIR__,"..","data","nl-pharmacies.csv"))
  if (redownload || !isfile(csvfile))
    r = HTTP.get("https://nlpb.in1touch.org/company/roster/companyRosterView.html?companyRosterId=12");
    h = parsehtml(String(r.body));  
    rows = eachmatch(Cascadia.Selector("div > div > table > tbody"),h.root);
    rows = rows[2:length(rows)];
    function parserowNL(row)
      name = nodeText(row.children[1].children[1])
      address = nodeText(row.children[2].children[1])
      street = nodeText(row.children[2].children[1].children[4])
      manager = nodeText(row.children[1].children[2])
      phone = nodeText(row.children[2].children[2].children[2])
      fax = nodeText(row.children[2].children[2].children[5])
      city = nodeText(row.children[2].children[1].children[5])
      txt = [name street address manager phone fax city ]
    end
    nl = DataFrame(vcat(parserowNL.(rows)...),
                   [:name, :street, :address, :manager,:phone, :fax ,:city ])
    nl[:street] = (a->replace(a, r"(P.O.)? ([Bb]ox)? \d+"s => s"")).(nl[:street])
    nl[:address] = (a->replace(a, r"(P.O.)? ([Bb]ox)? \d+"s => s"")).(nl[:address])
    nl[:address] = (a->replace(a, r"Licence #:[A-Z][A-Z]-\d+"s => s"")).(nl[:address])
    nl[:zip] = (a->replace(a,r".+(\p{L}\d\p{L}).?(\d\p{L}\d).*"s => s"\1 \2")).(nl[:address])
    nl[:city] = (a->replace(a,r"NL.*"s => s"")).(nl[:city])
    nl[:manager] = (a->replace(a,r"Pharmacist-in-Charge: \d+-\d+"s => s"")).(nl[:manager])
    nl[:province] = "NL"
    CSV.write(csvfile, nl)    
  else
    nl = CSV.read(csvfile)
  end
  return(nl)
end



"""
     loadPEdata(redownload=false)

Load or download data on PE pharmacies

Inputs:
- `redownload`: whether to redownload data even if csv file exists.
Output: 
- Dataframe containing information on pharmacies
"""
function loadPEdata(redownload=false)
  # Contributors: Liam MacDonald, Thomas Chan, Maria Rodriguez Vega
  csvfile=normpath(joinpath(@__DIR__,"..","data","pe-pharmacies.csv"))
  if (redownload || !isfile(csvfile)) 
    r = HTTP.get("https://pei.in1touch.org/client/roster/clientRosterView.html?clientRosterId=108");
    h = parsehtml(String(r.body)); 
    rows = eachmatch(Selector("div > div > div > table > tbody"), h.root);
    println(size(rows))
    rows = rows[2:length(rows)]; #first one is empty   
    function parserowPE(row)
      name = nodeText(row.children[1])
      tmp = nodeText.(row.children[2].children[1].children[1].children)
      manager = tmp[2]
      tmp = nodeText.(row.children[2].children[1].children[2].children)
      street = tmp[3]
      address = tmp[5]
      tmp = nodeText.(row.children[2].children[1].children[1].children[4].children)
      phone = tmp[2]
      fax = try #try and catch missing data error 
        fax = tmp[5]
      catch y
        if isa(y, BoundsError)
          fax = tmp[3]
        end
      end
      txt = [name manager street address phone fax]
    end
    pe = DataFrame(vcat(parserowPE.(rows)...),
                   [:name, :manager, :street, :address, :phone, :fax]) 
    pe[:province] = "PE"
    pe[:zip]  = (a->replace(a,r".+(\p{L}\d\p{L}).?(\d\p{L}\d).*"s => s"\1 \2")).(pe[:address])
    pe[:city] = (a->replace(a, r"(^.+), PE.+"s => s"\1")).(pe[:address])
    pe[:name] = (a->replace(a, r"(^.+), .+"s => s"\1")).(pe[:name])
    CSV.write(csvfile,pe)
  else
    pe = CSV.read(csvfile)
  end  
  return(pe)
end



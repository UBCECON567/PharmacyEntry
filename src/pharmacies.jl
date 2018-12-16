"""
    loadpharmacydata(;redownload=false) 
 
(Down)loads list of pharmacies in various Canadian provinces. 

Optional arguments:
  - `redownload` if true, will redownload source files, else tries to
     load from data directory

Output:
  - DataFrame listing pharamacies and their addresses

"""
function loadpharmacydata(;redownload=false)
  csvfile=normpath(joinpath(@__DIR__,"..","data","pharmacies.csv"))
  if (redownload || !isfile(csvfile))
    ## BC
    r = HTTP.get("http://www.bcpharmacists.org/list-community-pharmacies");
    h = parsehtml(String(r.body));
    
    rows = eachmatch(Selector("tr.odd, tr.even"), h.root);
    function parserow(row)
      fields = nodeText.(row.children)
      fields = reshape(fields, (1, length(fields)))
    end
    txt = vcat(parserow.(rows)...)
    bc = DataFrame(txt, [:name, :address, :manager, :phone, :fax])
    bc[:street] = (a->replace(a, r"(.+)\n(.+), BC.+\n.+"s => s"\1")).(bc[:address])
    bc[:city]   = (a->replace(a, r".+\n(.+), BC.+\n.+"s => s"\1")).(bc[:address])
    bc[:zip]    = (a->replace(a, r".+(\p{L}\d\p{L} \d\p{L}\d).+"s => s"\1")).(bc[:address])
    bc[:province] = "BC" 
    
    ## Manitoba
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
    mb[:zip]  = (a->match(r"(\p{L}\d\p{L} \d\p{L}\d)",a).match).(mb[:address])
    
    
    ## Additional province data can be found from links at
    ## https://www.pharmacists.ca/pharmacy-in-canada/directory-of-pharmacy-organizations/provincial-regulatory-authorities1/
    df = vcat(bc,mb)
    CSV.write(csvfile, df)
  else
    println("reading pharmacy data from $csvfile")
    df = CSV.read(csvfile)
  end
  df   
end






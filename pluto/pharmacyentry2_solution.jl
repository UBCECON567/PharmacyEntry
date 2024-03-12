### A Pluto.jl notebook ###
# v0.19.40

using Markdown
using InteractiveUtils

# ╔═╡ e72f87b2-a52a-4a31-9627-34e6daa73a78
using DataFrames, CSV, Downloads

# ╔═╡ e8645ac9-b8bf-44ac-8493-469c2d8c96da
using GeoIO, GeoStats, ZipFile, CairoMakie

# ╔═╡ a61534f2-aba5-4f43-9dc6-a87627c34f0d
using Proj

# ╔═╡ 8f0936ca-7595-4761-aa76-c61691fd2083
using ProgressLogging

# ╔═╡ 8d1de0e1-c587-4edb-98b7-8b6df440fe1d
using Distances

# ╔═╡ ce0751b6-9595-4cfc-9187-68449dfb2c63
using ComponentArrays

# ╔═╡ 8fc7a3de-c59f-46ad-a3de-37ba45e2e137
using Test, ForwardDiff

# ╔═╡ 7c87c2fa-1ffe-49eb-802b-160e004c10cd
using Optim

# ╔═╡ 751dab8a-f6a7-44fc-8fc0-a55ffd033f11
using PrettyTables, LinearAlgebra

# ╔═╡ 355a63ec-3179-4f95-b704-7ecedca419f2
begin 
	using ShortCodes
md"""
# References

$(br=DOI("10.1086/261786"))


"""
end

# ╔═╡ 35f22f38-c795-11ee-3ae2-f3a931be8cf3
md"""

Pharmacy Entry: Part II

Assignment for UBC ECON567

2024

This assignment and the previous one will estimate a model of pharmacy entry inspired by Bresnahan and Reiss (1991).

"""

# ╔═╡ f5a696d2-d0c0-495a-b62f-13ca08ad6f6d
begin
	import PlutoUI
	PlutoUI.TableOfContents()
end

# ╔═╡ 1b92f63e-04c1-41d5-84cb-69750b97cfc8
md"""
#  Data Preparation

In this section we reload the data that we prepared in Part I. 
"""

# ╔═╡ 3643ae60-c693-40b9-90c5-2d45c8c557b6
pharm = let  # pharm will be assigned to last statement before `end`
	csvfile = "pharmacies.csv"
	if !isfile(csvfile) # only download if the file doesn't already exist
		url = "https://raw.githubusercontent.com/UBCECON567/PharmacyEntry/master/data/pharmacies.csv"
		@warn "$csvfile not found. Downloading from $url and saving in $(pwd())."
		Downloads.download(url, csvfile)
	end
	df=CSV.read(csvfile, DataFrame) 
	df.lat[.!df.zipmatch] .= df.ziplat[.!df.zipmatch]
	df.lng[.!df.zipmatch] .= df.ziplng[.!df.zipmatch]
	df
end

# ╔═╡ e43048a7-f949-4ebc-8cfb-dc62d0b0d292
census = let
	csvfile = "popcentres.csv"
	if !isfile(csvfile)
		url = "https://raw.githubusercontent.com/UBCECON567/PharmacyEntry/master/data/popcentres.csv"
		@warn "$csvfile not found. Downloading from $url and saving in $(pwd())."
		Downloads.download(url, csvfile)
	end
	CSV.read(csvfile, DataFrame)	
end

# ╔═╡ 5f79fd4c-7ae0-4324-8736-454d27af3ab8
md"""

## Market Definitions

Many people correctly pointed out that there are some oddities with the markets that result from assigning each pharmacy to the nearest population centre. "Nearest" was being measured by straightline distance from the pharmacy to the centroid of the population centre. We can do somewhat better by using the official boundaries of the centres. 

"""

# ╔═╡ 7cc5801f-4d7f-4c91-8bc9-eb2b6c6dbeac
function downloadshp(url)
	shpzip = match(r"/([^/]+\.zip$)",url).captures[1]
	if !isfile(shpzip)
       Downloads.download(url,shpzip)
    end
	r=ZipFile.Reader(shpzip)
	tmpdir = mktempdir()
	for f in r.files
        file = joinpath(tmpdir,f.name)
        write(file, read(f))
    end
    close(r)	
	shp=replace(shpzip, "zip" => "shp")
	shp = joinpath(tmpdir,shp)
	pcshp = GeoIO.load(shp)
	rm(tmpdir, recursive=true)
	pcshp
end

# ╔═╡ 2ef7d268-9b9f-4d70-a927-1086d98404b7
md"""
First, we download a file containing population centre boundaries.
"""

# ╔═╡ 0783e0c6-e603-405a-9d18-1620ab3ea091
pcshp=downloadshp("http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers/2016/lpc_000b16a_e.zip");

# ╔═╡ 6e404cc0-05f6-45a7-949c-d2bd05c07fe1
md"""
For drawing a map, we also download a file of Province boundaries.
"""

# ╔═╡ 88579f53-3fcf-4f76-b57d-ca37a73a9711
Canada = downloadshp("https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpr_000b21a_e.zip")	;

# ╔═╡ 8bc8a608-ef52-4f40-946a-ef7a63503451
md"""
These shape files have much higher resolution than we need. To make drawing maps and other operations a bit faster, we reduce the number of points in the boundaries.
"""

# ╔═╡ 55ad2d43-eaa2-4bcf-8c89-b97a449e2e4e
can_simp = let
	ϵ = 10_000.0
	can_simp = deepcopy(Canada)
	can_simp.geometry = [GeoStats.decimate(g, ϵ, maxiter=100) for g in Canada.geometry]
	@show sum(nvertices.(Canada.geometry))
	@show sum(nvertices.(can_simp.geometry))
	can_simp
end;

# ╔═╡ d3fc5f23-9d7d-4973-afa5-6bc3478849eb
pc_simp = let
	ϵ = 50.0
	pc_simp = deepcopy(pcshp)
	pc_simp.geometry = [GeoStats.decimate(g, ϵ, maxiter=100) for g in pcshp.geometry]
	@show sum(nvertices.(pcshp.geometry))
	@show sum(nvertices.(pc_simp.geometry))
	pc_simp
end;

# ╔═╡ 16be52b4-7819-4aae-bebc-9cd1df63a8ce
md"""
Show some maps of the datasets. 

"""

# ╔═╡ 5e8fc45d-b13f-4c0f-8df4-26767e6c02cd
let 
	CairoMakie.activate!(type = "png") 
	fig,ax,plt=viz(can_simp.geometry, showfacets=true, alpha=0.4)
	viz!(ax,pc_simp.geometry, showfacets=false, color="red")
	hidedecorations!(ax)
	fig
end

# ╔═╡ 4ac7e2aa-f9bd-48ea-9052-79ea58724336
# https://www150.statcan.gc.ca/n1/pub/92-500-g/2016002/tbl/tbl_4.6-eng.htm
PRUIDtoname = [10=>"Newfoundland and Labrador", 
	11=>"Prince Edward Island",
	12=>"Nova Scotia",
	13=>"New Brunswick", 
	24=>"Quebec",
	35=>"Ontario",
	46=>"Manitoba",
	47=>"Saskatchewan",
	48=>"Alberta",
	59=>"British Columbia",
	60=>"Yukon",
	61=>"Northwest Territories", 
	62=>"Nunavut"];

# ╔═╡ 71583d73-21aa-4a09-aaca-7604707e48a7
let
	fltr = Filter(x->x.PRUID=="59")
	fig, ax, plt = viz(fltr(can_simp).geometry, showfacets=true,alpha=0.3)
	viz!(ax, fltr(pc_simp).geometry, showfacets=false, color="red")
	hidedecorations!(ax)
	fig
end

# ╔═╡ d00f473c-1cde-49a8-97e7-cd094b52a457
md"""

To assign pharmacies to markets, we will calculate the distance from each pharmacy to the nearest point within a population centre. Unfortunately, our pharmacy locations and population centre boundaries are in different coordinate systems. There are many geographic coordinate systems and converting between them can be confusing. The pharmacy locations are latitude and longitude. The population centre coordinates are in [Lambert conformal conic projection NAD83 with the origin placed somewhere reasonable for Canada.](https://www150.statcan.gc.ca/n1/pub/92-179-g/92-179-g2021001-eng.htm) This projection is also known as [EPSG:3347](https://epsg.io/3347). We will convert the pharmacy locations into this coordinate system using the `Proj.jl` package.

"""

# ╔═╡ 1e1787c1-6bae-45e5-b5ab-67b4e181c991
locs = let
	latlontolcc = Proj.Transformation("EPSG:4326", # latitude, longitude,
					 				   "EPSG:3347") # Canada's Lambert conformal coords
	pharm.loc = [GeoStats.Point(latlontolcc(row.lat, row.lng)) for row in eachrow(pharm)];
end;

# ╔═╡ ca2c4915-a392-4bde-bf5f-b9a4d1a240cf
md"""
Now we find the population centre closest to each pharmacy. We do this by drawing circles of increasing radius around each pharmacy and seeing if the circle intersects any pharmacy. The [Meshes.jl package is used](https://juliageometry.github.io/MeshesDocs/stable/predicates.html#point-geometry).  
"""

# ╔═╡ 6b9a2eed-a306-4e6c-98d4-9294e708c679
"""
    findmarket(location, markets; maxradius = 5_000., increment=maxradius/10)

Finds the closest market to `location`. Returns the index of the closest market and the distance to it. Returns `(missing, missing)` if there are no markets within `maxradius` meters of `location`.

## Details

First checks whether location is contained in any market. If not, then it creates balls around `location` of increasing radii up to `maxradius` in increments of `increment` and checks whether the ball intersects any market. 


"""
function findmarket(location, markets; maxradius = 5_000., increment=maxradius/10)
	m = findfirst(x->location ∈ x, markets.geometry)
	if !isnothing(m)
		return(m, 0.0)
	else
		for radius ∈ increment:increment:maxradius
			ball = Ball(location, radius)
			m = findfirst(x-> intersects(ball,x), markets.geometry)
			if !isnothing(m)
				return(m, radius)
			end
		end
	end
	return(missing, missing)
end

# ╔═╡ fcd663a3-6c82-478d-a3e2-0238835c1c8e
ndf = let
	maxr=50_000
	@progress closestindex = [findmarket(l, pc_simp, maxradius=maxr, increment=1000) for l in pharm.loc]
	nmiss = sum(ismissing(c[1]) for c in closestindex)
	@info "$nmiss of $(nrow(pharm)) pharmacies had no population centre within $maxr meters"
	pharm.PCUID = [ismissing(c[1]) ? missing : pc_simp.PCUID[c[1]] for c in closestindex]
	pharm.pcdistance = [c[2] for c in closestindex]	
	ndf = combine(groupby(pharm, :PCUID), nrow => :npharm)
	ndf.GEO_CODE = (x-> ismissing(x) ? x : parse(Int,x)).(ndf.PCUID)
	ndf
end;

# ╔═╡ e436f48b-4da7-47f9-a98b-bdc0324a3fb9
md"""
Let's check our work by drawing a map. 

The map below shows Vancouver surrounding population centres with the assigned pharmacies shown as dots of matching colors. 

"""

# ╔═╡ 62132f5b-1c25-4a8f-b662-d660da1aede2
let 
	rad = 150_000 # show pharmacies and population centres within this many meters 
	pc = Filter(r->r.PCNAME=="Abbotsford")(pc_simp)[1,:]
	pdf = Filter(r->intersects(Ball(r.loc,rad), pc.geometry) && !ismissing(r.PCUID))(pharm)
	pcs = Filter(r->r.PCUID ∈ skipmissing(pdf.PCUID))(pc_simp)
	cdf = DataFrame(:PCUID=>pcs.PCUID,:color=>sortperm(pcs.PCUID))
	pdf = leftjoin(pdf, cdf, on=:PCUID)
	fig, ax, plt = viz(pcs.geometry, color=cdf.color, alpha=0.4)
	viz!(ax,pdf.loc, color=pdf.color)
	hidedecorations!(ax)
	fig
end
		

# ╔═╡ 4db2d6aa-3224-4736-bd95-09d0d5aeba03
md"""

Now we merge the number of pharmacies with the market information from the census.
"""

# ╔═╡ 721c5720-fa31-4ded-9581-547fa2b37b3b
marketdf = let
	# number of firms by GEO_CODE
	df = leftjoin(census, ndf, on=:GEO_CODE, matchmissing=:notequal)
	# repalce missing with 0 
	df.nfirms = coalesce.(df.npharm, 0)
	df
end;


# ╔═╡ 4f71c1d1-8719-49f1-8325-c942b7fcf56f
md"""

Here are the population centres with more than 20 pharmacies.

"""

# ╔═╡ bd04e9a8-a5be-4880-92b5-b3db5d55c727
sort(filter(x->x.nfirms>=20, marketdf)[!, [:GEO_NAME, :PROV_TERR_NAME_NOM, Symbol("Population, 2016"), :nfirms]], :nfirms, rev=true)

# ╔═╡ 3a0c815b-b97a-4a45-b843-1ca10a4e6f25
sort(marketdf, Symbol("Population, 2016"), rev=true)[!, [:GEO_NAME, :nfirms, Symbol("Population, 2016")]]

# ╔═╡ 30eb77d2-adc6-43e3-b015-dce8df01f6a9
md"""

That looks pretty reasonable. 

### Problem 1

!!! question "Problem 1"
    For estimation, we might want to further limit the sample used. Remember that the Bresnehan and Reiss (1991) model assumes that all firms in the same market compete with on another, and that firms in different markets do not affect one another. Given this are there any markets that we should omit from the estimation?  (If you need documentation for the variable definitions, the population centre data is from the [2016 Census Profile](https://www12.statcan.gc.ca/census-recensement/2016/dp-pd/prof/details/page.cfm?Lang=E&Geo1=CSD&Geo2=PR&Code2=01&SearchType=Begins&SearchPR=01&TABID=1&B1=All&type=0&Code1=5915022&SearchText=vancouver.))

"""

# ╔═╡ a222d660-f8c1-432a-babd-2dc479234c10
md"""

In large markets, like Vancouver, not all pharmacies compete with one another.  

Also, in markets that are too close together, consumers in one market might visit pharmacies in another. 

Many people noted the large number of markets with 0 pharmacies. That is because the redownloaded census data above included all provinces, but we did not get pharmacy locations for all provinces. We should drop the provinces for which we did not scrape pharmacies. 

"""

# ╔═╡ c7990171-41dc-43aa-84fd-6767b8c9ecdb
# distances between population centres in km
distances = [Distances.haversine((x.lng, x.lat), (y.lng, y.lat), 6372.8) 
	for (x,y) in Iterators.product(eachrow(marketdf), eachrow(marketdf))]


# ╔═╡ 6177a6bf-091d-403d-a414-596838af298c
marketdf[!,:mindist]=vec(minimum(distances + I*Inf, dims=2))

# ╔═╡ 75d06b80-d99a-452f-9de7-eb816412a00e
estdf = let
	tmp = combine(groupby(marketdf, :PROV_TERR_NAME_NOM), :nfirms=>sum)
	provs = unique(tmp.PROV_TERR_NAME_NOM[tmp.nfirms_sum.>10])
	filter(x->(x[Symbol("Population, 2016")] < 1e5 && x.mindist>10 && x.PROV_TERR_NAME_NOM ∈ provs), marketdf)
end

# ╔═╡ 179c1a07-f0b3-4b83-b3d2-5746bbd7bd4e
size(estdf)

# ╔═╡ 29615fc6-242c-4bb0-8353-cef2f3b714c9
sort(estdf, :nfirms, rev=true)[!,[:GEO_NAME, :nfirms, Symbol("Population, 2016"), :mindist]]

# ╔═╡ 3652325a-faf2-48fb-8c98-5cbfd32848b1
hist(estdf.nfirms)

# ╔═╡ e4f8347b-b022-4328-ba40-a8138bdc2ad0
(maximum(estdf.nfirms) != 1) || error("Modify the filtering for estdf in the cell above")

# ╔═╡ cbbf20ca-fb2c-480e-a56b-527a4fa3daeb
md"""

# Model 

"""

# ╔═╡ 2bc94ef3-70bd-4b0e-b2d8-962fd79b7650
md"""
As in Bresnehan and Reiss (1991), we will assume that the profits per pharmacy in
market $m$ with $N$ pharmacies is 

```math
\begin{align*}
    \pi_{m,N} = s_m \underbrace{(\alpha_1 + x_m\beta + \sum_{n=2}^N
    \alpha_n)}_{\text{variable profits}} - \underbrace{\left(\gamma_1 + \delta
    w_m + \sum_{n=2}^N \gamma_n \right)}_{\text{fixed costs}} +
    \epsilon_m 
\end{align*}
```

where $s_m$ is the size of the market. 

## Simulation

To check our estimation code and perhaps to simulate counterfactuals, we provide a function to simulation the model.

"""


# ╔═╡ 95078d1c-c4ec-4d6b-99ac-20a0c96bf242
""" 
         brentrysim(data::AbstractDataFrame,
                    s::Symbol,
                    x::Array{Symbol,1},
                    w::Array{Symbol,1},
                    α,β,γ,δ;
                    distϵ)

Simulates Bresnehan & Reiss style entry model

Inputs:
- `data` DataFrame 
- `s` name of market size variable in data
- `x` array of names of variable profit shifters
- `w` array of names of fixed cost shifters 
- `α, β, γ, δ` model parameters, see above
- `distϵ` distribution of ϵ, optional, defaults to standard normal

The same variables may be included in both `x` and `w`.

Output:
- `N` vector of length nrow(data) giving the simulated number of firms
   in each market. Will be missing for observations with any of s, x, or
   w missing. 
"""
function brentrysim(data::AbstractDataFrame,
                    s::Symbol,
                    x::Array{Symbol,1},
                    w::Array{Symbol,1},
                    α,β,γ,δ;
                    distϵ = Normal())  
  variables = unique([s, x..., w...])
  inc = completecases(data[!,variables])
  S = disallowmissing(data[!,s][inc])
  X = disallowmissing(Matrix(data[!,x][inc,:]))
  W = disallowmissing(Matrix(data[!,w][inc,:]))
  ϵ = rand(distϵ, length(S))
  
  π0 = S.*(X*β) - W*δ + ϵ
  π = similar(π0, length(S), length(α)+1)
  for n in 1:length(α)
    π[:,n] = π0 + S*sum(α[1:n]) .- sum(γ[1:n])
  end
  π[:,length(α)+1] .= -Inf
  if !all(mapslices(issorted, -π, dims=2))
	  @show π
	  error("π is not always decreasing with n, check your parameters")	
  end
  n = mapslices(x->findfirst(x.<0), π, dims=2)
  n = n .- 1
  if (sum(inc) != length(inc)) 
    N = Array{Union{Missing, Integer},1}(undef, nrow(data))
    N .= missing
    N[inc] = n
  else
    N = vec(n)
  end
  return(N)
end


# ╔═╡ 00bbe80e-5c40-4d37-9c9d-1d871f61c72c
md"""

## Likelihood

Let $\theta = (\alpha, \beta, \gamma)$ denote the model parameters.
If we assume $\epsilon_m$ has cdf $F_\epsilon()$ (conditional on $s$,
$x$, and $w$), then the likelihood of observing $N_m$ pharmacies in
market $m$ is

```math
\begin{align*}
   P(N | s, x, w; \theta) = & P(\pi_{N} \geq 0 \;\&\;
   \pi_{N+1} < 0) \\
   = & P\left(
\begin{array}{c} -\left[s (\alpha_1 + x\beta + \sum_{n=2}^{N}
    \alpha_n) - \left(\gamma_1 + \delta
    w + \sum_{n=2}^{N} \gamma_n \right)\right] \leq \epsilon \text{ and}\\
    \text{and } \epsilon \leq -\left[s (\alpha_1 + x\beta + \sum_{n=2}^{N+1}
    \alpha_n) - \left(\gamma_1 + \delta
    w + \sum_{n=2}^{N+1} \gamma_n \right)\right] \end{array} \right) \\
   = & F_\epsilon\left(-\left[s (\alpha_1 + x\beta + \sum_{n=2}^{N+1}
    \alpha_n) - \left(\gamma_1 + \delta
    w + \sum_{n=2}^{N+1} \gamma_n \right)\right]\right) - \\
    & - F_\epsilon\left( -\left[s (\alpha_1 + x\beta + \sum_{n=2}^{N}
    \alpha_n) - \left(\gamma_1 + \delta
    w + \sum_{n=2}^{N} \gamma_n \right)\right] \right)
\end{align*}
```

The loglikelihood is then

```math
\mathcal{L}(\theta) = \frac{1}{M} \sum_{m=1}^M \log P(N = N_m | s_m, x_m, w_m;
\theta),
```

and $\theta$ can be estimated by maximizing,

```math
\hat{\theta} = \mathrm{arg}\max_\theta \mathcal{L}(\theta).
```

"""

# ╔═╡ 94688148-4207-4843-bd55-1a81f98061cf
md"""

### Problem 2

!!! question "Problem 2"
    Write a function to calculate the likelihood. Some skeleton code is provided below to get you started. 


"""

# ╔═╡ ca15fc94-be19-4a9c-82fc-8fa98e61f06d
"""
     logfinite(cut)

  Returns a function that computes log(x) if x>=cut, else the first order taylor
  expansion of log(x) around cut if x<cut. 


  Main purpose is to avoid returning -Inf while maximizing a log
  likelihood.  
"""
function logfinite(cut::Number)
  lc = log(cut)
  dlc =1.0/cut
  function(x)
    if (x>=cut)
      log(x)
    else
      lc + (x-cut)*dlc
    end
  end
end


# ╔═╡ 3a8adc6d-8fcc-4f17-81be-e45e058b1412
"""
         brentrymodel(data::AbstractDataFrame,
                      n::Symbol,
                      s::Symbol,
                      x::Array{Symbol,1},
                      w::Array{Symbol,1};
                      Fϵ)

Create loglikelihood for Bresnehan & Reiss style entry model

## Inputs:
- `data` DataFrame 
- `n` name of number of firm variable in data
- `s` name of market size variable in data
- `x` array of names of variable profit shifters
- `w` array of names of fixed cost shifters 
- `Fϵ` cdf of ϵ, optional, defaults to standard normal cdf

The same variables may be included in both `x` and `w`.
"""
function brentrymodel(data, #::AbstractDataFrame,
                      n::Symbol,
                      s::Symbol,
                      x::Array{Symbol,1},
                      w::Array{Symbol,1};
                      Fϵ = x->cdf(Normal(),x))
	# skip observations with missings
    variables = unique([n,s, x..., w...])
    inc = completecases(data[!,variables])
    S = disallowmissing(data[!,s][inc])
    X = disallowmissing(Matrix(data[!,x][inc,:]))
    W = disallowmissing(Matrix(data[!,w][inc,:]))
    N = disallowmissing(data[!,n][inc])

    function packparam(α,β,γ,δ)
	θ = ComponentArray(α=α,β=β,γ=γ,δ=δ)
    end
    function unpackparam(θ) #::ComponentArray)
	(θ.α,θ.β,θ.γ,θ.δ)
    end

    logf = logfinite(1e-6)

    function loglike(θ)
        (α,β,γ,δ) = unpackparam(θ)
        csα = cumsum(α)
        csγ = cumsum(γ)
        π0 = S.*(X*β) - W*δ
        function lli(π0, n, s)
            if n == 0
                return logf(Fϵ(-(π0 + s*α[1] - γ[1])))
            elseif n==length(α)
                return logf(1 - Fϵ(-(π0 + s*csα[n] - csγ[n])))
            else
                return logf(Fϵ(-(π0 + s*csα[n+1] - csγ[n+1])) - Fϵ(-(π0 + s*csα[n] - csγ[n])))
            end
        end
        sum(lli(p0, ni, si) for (p0, ni, si) in zip(π0, N, S)) / length(N)
    end

    return(loglike=loglike, unpack=unpackparam, pack=packparam)
end


# ╔═╡ 445fae4b-b84a-4de2-9ebd-aeac22340c2d
md"""

Here are some very simple tests that your function returns a number and is compatible with `ForwardDiff`. These tests do not check for correctness.
"""

# ╔═╡ 3c1138db-5cb3-4bc4-bec6-0a06ee720343
@testset begin
	estdf[!,:pop10k] = estdf[!,Symbol("Population, 2016")]./10_000
	tmp = filter(x->x.nfirms < 3, estdf)
	loglike, unpack, pack = brentrymodel(tmp, :nfirms, :pop10k, [Symbol("Employment rate")], [Symbol("Employment rate")])
	α = [2.0, -1.5, -1.0]
	γ = [0.0, 1.0, 2.0]
	β = ones(1)
	δ = ones(1)	
	@test unpack(pack(α, β, γ, δ)) == (α, β, γ, δ)
	θ = pack(α, β, γ, δ)
	@test θ == pack(unpack(θ)...)
	@test isfinite(loglike(θ))
	@test all(isfinite.(ForwardDiff.gradient(loglike, θ)))
end

# ╔═╡ 44027f7b-530b-4498-b60e-4140514a5d53
md"""
### Testing the Likelihood on Simulated Data

Now we test your likelihood on simulated data. You can change the parameters and/or variables used in the next cell, but you do not need to. 

"""

# ╔═╡ 1873c5b7-9a20-431b-8324-63585796f040
begin
	βs = [1., -0.1]
	δs = [1., 1.]
	αs = [1.0, -0.5, -1.0, -2.0, -2.0]
	γs = [0.0, 0.2, 0.2, 0.2, 0.4]
	svar_sim = :pop10k
	xvars_sim = [:income10k,
         	:mediumage]
	wvars_sim = [:logdensity,
    	     :logarea]
end

# ╔═╡ 54edbf03-59c2-4759-8e5b-8ee616fef264
simdf=let 
	df = deepcopy(estdf)
	# Important to scale variables to avoid numerical problems in both
    # simulation & estimation
	df[!,:pop10k] = df[!,Symbol("Population, 2016")]./10000
	df[!,:logpop10k] = log.(df[!,:pop10k])
	df[!,:income10k] = df[!,Symbol("Average total income in 2015 among recipients (\$)")]./10000
	df[!,:density1k] = df[!,Symbol("Population density per square kilometre")]./1000
	df[!,:logdensity] = log.(df[!,:density1k])
	df[!,:logarea] = log.(df[!,Symbol("Land area in square kilometres")])
	df[!,:mediumage] = df[!,Symbol("15 to 64 years")]./100
	
	df.nsim = brentrysim(df, svar_sim, xvars_sim, wvars_sim, αs, βs, γs, δs)
	df
end;

# ╔═╡ 1bc014b5-f00d-4e24-b27a-104219527410
hist(simdf.nsim)

# ╔═╡ 711971fb-0315-4095-b3c8-13d402d2fdec
md"""

The cell below will maximize the likelihood. A subsequent creates a table showing the parameters used to simulate the data and the estimated parameters. The estimated parameters should be somewhat close to the true ones. 


### Problem 3

!!! question "Problem 3"
    Check that your likelihood results in parameters near the true values. If you suspect a problem with your code, briefly write what seems wrong.

"""

# ╔═╡ b860236e-91c3-41ae-81a0-be4c39130b65
loglikes, unpacks, packs, θ̂s = let		
	loglike, unpack, pack = 
		brentrymodel(simdf, :nsim, svar_sim, xvars_sim, wvars_sim)
	
	θ0 = pack(αs,βs,γs,δs)
	loglike(θ0)
	@show res = optimize(x->-loglike(x), θ0, LBFGS(), autodiff=:forward)
	@test res.g_converged
	loglike, unpack, pack, res.minimizer
end

# ╔═╡ d05308bb-f2d3-430f-ac3b-7bd2c121ef22


# ╔═╡ e65bacaa-da89-453c-bea0-e30606dde0d6
"""
    setable(θ̂, loglike, nmarkets, θtruth=nothing)

Computes the asymptotic variance of θ̂, and creates a table of estimates and standard errors.

## Arguments

- `θ̂`  maximizer of `loglike`
- `loglike` is the loglikelihood function
- `nmarkets` the number of markets
- `θtruth` optional. If omitted, the corresponding column will not be printed.

## Returns

`(table, varianceθ)`
"""
function setable(θ̂, loglike, nmarkets, θtruth=nothing)
	# calculate standard errors
    H = ForwardDiff.hessian(loglike,θ̂)
    Varθ =  try 
		-inv(H)./nmarkets
	catch 
		@warn "Hessian is singular, se are incorrect"
		-inv(H - I)./nmarkets
	end
    # Make a nice(ish) table
	if (isnothing(θtruth))
		header= ["Estimate", "(SE)"]
		values = hcat(θ̂, sqrt.(diag(Varθ)))
		h1 = nothing
		fmter = (v,i,j) -> (j==2) ? "($(round(v,digits=3)))" : round(v, digits=3)
		hl = ()
	else 
		header= ["Truth", "Estimate", "(SE)"]
		values = hcat(θtruth, θ̂, sqrt.(diag(Varθ)))
		# highlight estimates that reject H0 : estimate = true at 95% level
		h1 = HtmlHighlighter(
	  		(tbl, i, j)->(j==2) &&
                   		abs(tbl[i,1]-tbl[i,2])/tbl[i,3]>quantile(Normal(),0.975),
  			HtmlDecoration(color="red"))
		hl = tuple(h1)
		fmter = (v,i,j) -> (j==3) ? "($(round(v,digits=3)))" : round(v, digits=3)
	end
	tbl=pretty_table(HTML, values, 
		             header=header,
		             row_labels=ComponentArrays.labels(θ̂),
                     highlighters=hl,
	                 formatters = tuple(fmter))
	return(tbl, Varθ)
end

# ╔═╡ a7202a46-f7f4-4b7e-94a0-73354a6b28f1
let 
	tbl, V = setable(θ̂s, loglikes, sum(.!ismissing.(simdf.nsim)),
		packs(αs,βs, γs, δs))
	tbl
end

# ╔═╡ fc63d341-4692-480f-bab7-5228e53ba8b5
md"""
The estimates on simulated data look fine. 

"""

# ╔═╡ a9acb09e-8cc0-463a-afaa-637799dd70d3
md"""
# Estimation 

### Problem 4

!!! question "Problem 4"
    Estimate the model on the real data. Briefly discuss your choice of "X" and
    "W" variables. Be sure to check the output of `optimize().` You may
    have to do some tweaking of initial values and/or optimization
    algorithm to get convergence. As in the simulation, report both your
    parameter estimates and standard errors. (For standard errors, you can use the `setable` function, omitting its last argument.)


"""

# ╔═╡ 1afaeaca-e8d8-4e30-a9de-5a109f6384a7
names(estdf)

# ╔═╡ e1bb92d0-24f5-4b08-a095-2e9a11ba3807
md"""

I use population as market size. As variable profit shifters, I include income and the portion of the population of working age. As fixed cost shifters, I include only  area. There are many other reasonable choices. Given the samewhat limited sample size, a somewhat parsimonious specification makes sense.


"""

# ╔═╡ c1b1dfe5-6da7-4256-bfa0-715a6ebe68e7
# Your estimation code, it will be similar to the code provided after Problem 3
edf=let 
	df = deepcopy(estdf)
	# Important to scale variables to avoid numerical problems in both
    # simulation & estimation
	df[!,:pop10k] = df[!,Symbol("Population, 2016")]./10000
	df[!,:logpop10k] = log.(df[!,:pop10k])
	df[!,:income10k] = df[!,Symbol("Average total income in 2015 among recipients (\$)")]./10000
	df[!,:density1k] = df[!,Symbol("Population density per square kilometre")]./1000
	df[!,:logdensity] = log.(df[!,:density1k])
	df[!,:logarea] = log.(df[!,Symbol("Land area in square kilometres")])
	df[!,:mediumage] = df[!,Symbol("15 to 64 years")]./100
	df
end;

# ╔═╡ b11e27d2-a294-4e9f-bcbd-eb29fe598f06
begin
	svar = :pop10k
	xvars = [:income10k, :mediumage]
	wvars = [:logarea]
end;

# ╔═╡ 31669dab-b7a2-45e0-a373-89239b4ddad1
loglike, unpack, pack, θ̂ = let		
	loglike, unpack, pack = try 
		# run my solulution code from another file
		include("solution2.jl") 
		brentrymodel_sol(edf, :nfirms, svar, xvars, wvars)		
	catch
		# if solution2.jl doesn't exist, use your brentrymodel function defined above
		brentrymodel(simdf, :nfirms, svar, xvars, wvars)
	end
	α0 = [1, -ones(maximum(edf.nfirms)-1)./10...]
	γ0 = ones(maximum(edf.nfirms))/10
	β0 = ones(length(xvars))
	δ0 = ones(length(wvars))
	θ0 = pack(α0,β0,γ0,δ0)
	loglike(θ0)
	θl = pack(-Inf*ones(length(α0)), -Inf*β0, [-Inf, zeros(length(γ0)-1)...], -Inf*δ0)
	θh = pack([Inf, zeros(length(α0)-1)...], Inf*β0, Inf*ones(length(γ0)), Inf*δ0)
	@show res = optimize(x->-loglike(x), θl, θh, θ0, Fminbox(BFGS()), autodiff=:forward) #, 
	   #Optim.Options(iterations=10_000))
	#@test res.g_converged
	loglike, unpack, pack, res.minimizer
end

# ╔═╡ 1edf49d4-e61b-43ab-b9f8-e7f2b49773aa
loglike2, unpack2, pack2, θ̂2 = let		
	loglike, unpack, pack = try 
		# run my solulution code from another file
		include("solution2.jl") 
		brentrymodel_sol(edf, :nfirms, svar, xvars, wvars)		
	catch
		# if solution2.jl doesn't exist, use your brentrymodel function defined above
		brentrymodel(simdf, :nfirms, svar, xvars, wvars)
	end
	
	linN = 10
	maxN = maximum(edf.nfirms)
	α0 = [1, -ones(linN-1)./10...]
	γ0 = ones(linN)/10
	pack2(α, β, γ, δ) = pack(α[1:linN], β, γ[1:linN], δ)
	function unpack2(θ)
		β = copy(θ.β)
		δ = copy(θ.δ)
		α1= copy(θ.α)
		γ1 = copy(θ.γ)
		λ = log(-α1[linN])-log(-α1[linN-1])
		a = α1[linN]/exp(λ*linN)
		#@show a == α1[linN-1]/exp(λ*(linN-1))
		α = vcat(α1, a*exp.(λ*(linN+1:maxN)))

		λ = log(γ1[linN])-log(γ1[linN-1])
		a = γ1[linN]/exp(λ*linN)
		γ = vcat(γ1, a*exp.(λ*(linN+1:maxN)))
		α, β, γ, δ
	end
	β0 = ones(length(xvars))
	δ0 = ones(length(wvars))
	θ0 = pack2(α0,β0,γ0,δ0)
	
	@show loglike(pack(unpack2(θ0)...))

	θl = pack(-Inf*ones(length(α0)), -Inf*β0, [-Inf, zeros(length(γ0)-1)...], -Inf*δ0)
	θh = pack([Inf, zeros(length(α0)-1)...], Inf*β0, Inf*ones(length(γ0)), Inf*δ0)
	@show res = optimize(x->-loglike(pack(unpack2(x)...)), θl, θh, θ0, Fminbox(BFGS()), autodiff=:forward) #, 
	 #  Optim.Options(iterations=10_000))
	#@test res.g_converged
	loglike, unpack2, pack2, res.minimizer
end

# ╔═╡ 3c344dce-4648-41f4-b341-eba7705be7b7
md"""
For estimation, I impose constraints that variable profits weakly decrease with n and fixed costs weakly increase with n. This means constraining alpha to be negative and gamma to be positive. I do this using the Fminbox optimizer. 
"""

# ╔═╡ a5c603f8-9e16-4f77-bea2-f5c05939c3eb
θ̂

# ╔═╡ 94513167-c3c4-45f5-8ff7-8ba77277a61f
sort(unique(edf.nfirms))

# ╔═╡ 4c7356d8-b5a9-40f8-a13c-405fc256d9f4
# Table of parameters and standard errors
(tab, V) = setable(θ̂ , loglike, nrow(edf))

# ╔═╡ e353e3c3-b9e0-4998-82ed-73ab000433b6
md"""
As shown many of the α and γ are zero. This is related to the fact that we observe no markets with some numbers of firms (e.g. there are no markets with 30-34 firms). If we never observe a certain number of firms, then the likelihood will be maximized by making that number of firms never occur.  

This leads to problems in computing standard errors, showing up as a singular Hessian. 

To avoid this problem, we can use a more restrictive parameterization. Specifically, instead of making α[n] a separate parameter for each n, we will make α[n] a parametric function of n for larger n. We have seen this done in various entry papers. 
"""

# ╔═╡ f323c5e7-8bad-4854-91e2-154ec0d1cb95
(tab2, V2) = setable(θ̂2, x->loglike2(pack(unpack2(x)...)), nrow(edf))

# ╔═╡ c275ddec-d58c-4f29-886a-f79681d73523
md"""
The model is parameterized so that for $n>10$, the ratio of $\alpha[n]/\alpha[n-1]$ is the same as $\alpha[9]/\alpha[10]$. $\gamma$ for $n>10$ are similarly defined. The figure below shows the full set of $\alpha$ and $\gamma$, along with pointwise 95% confidence bands.
"""

# ╔═╡ 23c7306c-3f59-4a78-8dac-0dceebf451d5
let
	α, β, γ, δ = unpack2(θ̂2)
	Ja = ForwardDiff.jacobian(θ->unpack2(θ)[1], θ̂2)
	Jg = ForwardDiff.jacobian(θ->unpack2(θ)[3], θ̂2)

	Va = Ja*V2*Ja'
	Vg = Jg*V2*Jg'

	
	f = Figure()
	n = 1:length(α)
	lines(f[1,1],1:length(α), α, label="α", 
	   axis = (; title = "α", xlabel = "n", ylabel = "α̂"))
	poly!(f[1,1],CairoMakie.Point2.(vcat(n, reverse(n)), 
		vcat(α .- sqrt.(diag(Va))*1.96, reverse(α .+ sqrt.(diag(Va))*1.96))), alpha=0.3)
	lines(f[2,1],1:length(γ), γ, label="γ", 
		axis = (; title = "γ", xlabel = "n", ylabel = "γ̂"))
	poly!(f[2,1],CairoMakie.Point2.(vcat(n, reverse(n)), 
		vcat(γ .- sqrt.(diag(Vg))*1.96, reverse(γ .+ sqrt.(diag(Vg))*1.96))), alpha=0.3)
	f
end
	

# ╔═╡ 5603031d-61e3-4c25-b38f-a3cc480106b6
md"""
# Results

## Fit

### Problem 5

!!! question "Problem 5" 
    Create tables and/or figures that show how well your estimates and model fit the data. 

"""



# ╔═╡ ad7a0a32-36f3-42e1-9ff6-18d761d6b348
nsim = let 
	simsper =   100
	paramdraws= 200
	nsim = Array{typeof(edf.nfirms),2}(undef, paramdraws, simsper)	
	for i in 1:paramdraws
		if (i>1)
			θ = deepcopy(θ̂2)
			θ .= rand(MvNormal(θ̂2, Hermitian(V2)))
			θ.α[2:end] .= min.(θ.α[2:end], -eps())
			θ.γ[2:end] .= max.(θ.γ[2:end], eps())
		else
			θ = θ̂2
		end
		α, β, γ, δ = unpack2(θ)
		for j in 1:simsper
			nsim[i,j] = brentrysim(edf, svar, xvars, wvars, α, β, γ, δ)
		end
	end
	nsim
end;

# ╔═╡ 172ea51b-2831-412e-a044-994af0bafb16
let
	fig = Figure()
	hist(fig[1,1],edf.nfirms, bins=maximum(edf.nfirms), normalization=:probability,
	axis = (; title = "Observed and Fitted Number of Firms", xlabel = "Number of Firms", ylabel = "P(market has n firms)"))
	pn = [[mean(mean(N.==n) for N in nsim[j,:]) for n in 0:maximum(edf.nfirms)] 
		for j in 1:size(nsim,1)]
	P = pn[1]
	ci = [quantile([pn[s][n] for s in 2:length(pn)], [0.05, 0.95]) 
			for n in 1:length(P)]
	lb = [p - c[1] for (p,c) in zip(P,ci)]
	ub = [c[2] - p for (p,c) in zip(P,ci)]
	n = (1:length(P)) .- 0.5
	scatter!(fig[1,1],n, P, color=:red, makersize=10)
	errorbars!(fig[1,1],n, P, lb, ub, color=:red, whiskerwidth=6)
	fig
	#lines!(fig[1,1],1:10,1:10)
	#fig
end

# ╔═╡ bb835ca1-bc55-4322-8449-0351dd9137c0
md"""
The figure above shows the observed and fitted distribution of number of pharmacies among markets. The error bars show 90% confidence intervals around the fitted distribution. 

The model is underpredicting 0 and overpredicting 1 and 2 pharmacies. This might be worth looking into. There could be a problem with the estimation and/or model.
"""

# ╔═╡ ca66910d-1c61-47ab-bbaa-da80dcefb462
md"""

## Competitiveness

### Problem 6

!!! question "Problem 6"
    Compute entry thresholds and create a figure similar to Figure 4 from Bresnahan and Reiss (1991). Since this data generally has more pharmacies, you should probably choose something larger than 5 for the maximum N to plot. Use the delta method to compute standard errors for your $s_N$ and add confidence bands to the figure. Briefly interpret the results.

"""

# ╔═╡ 3bb77367-0947-4d0b-89e9-e1c75a73388d
function sizethresholds(α, β, γ, δ, X, W; ϵ = 0)
	S = [((W*δ)[1] + sum(γ[1:n]) - ϵ) / ((X*β)[1] + sum(α[1:n])) for n in 1:length(α)]
end

# ╔═╡ 603564a1-b813-47a9-931a-98055a21b373
let 
	X = mean(Matrix(edf[!, xvars]), dims=1)
	W = mean(Matrix(edf[!, wvars]), dims=1)
	S = sizethresholds(unpack2(θ̂2)..., X, W, ϵ=0)*10_000
	n = 1:length(S)
	J = ForwardDiff.jacobian(θ->sizethresholds(unpack2(θ)...,X,W)./n*10_000, θ̂2)
	Vs = J*V2*J'
	f = Figure()
	scatter(f[1,1],n,S./n; 
		axis=(;title="Population per firm", xlabel="n", ylabel="Sₙ"))
	errorbars!(f[1,1],n,S./n,sqrt.(diag(Vs))*1.96, sqrt.(diag(Vs))*1.96)
	@show (S./n)[end]

	function rs(θ) 
		S=sizethresholds(unpack2(θ)..., X, W, ϵ=0)*10_000 ./n
		S./S[end]
	end
	rS = rs(θ̂2)
	Jr = ForwardDiff.jacobian(rs, θ̂2)
	Vr = Jr*V2*Jr'

	scatter(f[2,1],n,rS,
		axis=(;title="Relative size threshold", xlabel="n", ylabel="Sₙ/S₃₅"))
	errorbars!(f[2,1],n,rS,sqrt.(diag(Vr))*1.96, sqrt.(diag(Vr))*1.96)
	f	
end

# ╔═╡ 710f0258-5eb9-44d5-9b47-7a816615a23a
md"""
The figure above shows the estimated minimum population per pharmacy needed for $n$ pharmacies to enter when $X$ and $W$ are at their mean and $\epsilon=0$. 
The figure includes 95% confidence bands. 

The estimates show that the population per firm increases sharply with the number of firms. This suggests that there could be substantial market power. Monopoly firms need far fewer people to be viable than each firm in a market with many firms need. Even markets with 7 pharmacies appear to require fewer people per firm than markets with more pharmacies. This suggests that even with 7 pharmacies, the pharmacies have market power and earn more profits per person than in markets with more pharmacies.
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
ComponentArrays = "b0b7db55-cfe3-40fc-9ded-d10e2dbeff66"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Distances = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
Downloads = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
GeoIO = "f5a160d5-e41d-4189-8b61-d57781c419e3"
GeoStats = "dcc97b0b-8ce5-5539-9008-bb190f959ef6"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
Optim = "429524aa-4258-5aef-a3af-852621145aeb"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
PrettyTables = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
ProgressLogging = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
Proj = "c94c279d-25a6-4763-9509-64d165bea63e"
ShortCodes = "f62ebe17-55c5-4640-972f-b59c0dd11ccf"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
ZipFile = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"

[compat]
CSV = "~0.10.12"
CairoMakie = "~0.11.8"
ComponentArrays = "~0.15.8"
DataFrames = "~1.6.1"
Distances = "~0.10.11"
ForwardDiff = "~0.10.36"
GeoIO = "~1.12.7"
GeoStats = "~0.51.0"
Optim = "~1.9.2"
PlutoUI = "~0.7.55"
PrettyTables = "~2.3.1"
ProgressLogging = "~0.1.4"
Proj = "~1.7.0"
ShortCodes = "~0.3.6"
ZipFile = "~0.10.1"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.10.2"
manifest_format = "2.0"
project_hash = "f77b714237a3b8fed14f1a084abf1cfab5459b6d"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "d92ad398961a3ed262d8bf04a1a2b8340f915fef"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.5.0"
weakdeps = ["ChainRulesCore", "Test"]

    [deps.AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"
    AbstractFFTsTestExt = "Test"

[[deps.AbstractLattices]]
git-tree-sha1 = "222ee9e50b98f51b5d78feb93dd928880df35f06"
uuid = "398f06c4-4d28-53ec-89ca-5b2656b7603d"
version = "0.3.0"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "c278dfab760520b8bb7e9511b968bf4ba38b7acc"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.2.3"

[[deps.AbstractTrees]]
git-tree-sha1 = "faa260e4cb5aba097a73fab382dd4b5819d8ec8c"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.4.4"

[[deps.Accessors]]
deps = ["CompositionsBase", "ConstructionBase", "Dates", "InverseFunctions", "LinearAlgebra", "MacroTools", "Test"]
git-tree-sha1 = "cb96992f1bec110ad211b7e410e57ddf7944c16f"
uuid = "7d9f7c33-5ae7-4f3b-8dc6-eff91059b697"
version = "0.1.35"

    [deps.Accessors.extensions]
    AccessorsAxisKeysExt = "AxisKeys"
    AccessorsIntervalSetsExt = "IntervalSets"
    AccessorsStaticArraysExt = "StaticArrays"
    AccessorsStructArraysExt = "StructArrays"

    [deps.Accessors.weakdeps]
    AxisKeys = "94b1ba4f-4ee9-5380-92f1-94cde586c3c5"
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    Requires = "ae029012-a4dd-5104-9daa-d747884805df"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
    StructArrays = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"

[[deps.Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "0fb305e0253fd4e833d486914367a2ee2c2e78d0"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "4.0.1"
weakdeps = ["StaticArrays"]

    [deps.Adapt.extensions]
    AdaptStaticArraysExt = "StaticArrays"

[[deps.Animations]]
deps = ["Colors"]
git-tree-sha1 = "e81c509d2c8e49592413bfb0bb3b08150056c79d"
uuid = "27a7e980-b3e6-11e9-2bcd-0b925532e340"
version = "0.4.1"

[[deps.ArchGDAL]]
deps = ["CEnum", "ColorTypes", "Dates", "DiskArrays", "Extents", "GDAL", "GeoFormatTypes", "GeoInterface", "GeoInterfaceRecipes", "ImageCore", "Tables"]
git-tree-sha1 = "8168d1cea4d02ae2a36022d8d681d94cbcd69b47"
uuid = "c9ce4bd3-c3d5-55b8-8973-c0e20141b8c3"
version = "0.10.2"

[[deps.ArgCheck]]
git-tree-sha1 = "a3a402a35a2f7e0b87828ccabbd5ebfbebe356b4"
uuid = "dce04be8-c92d-5529-be00-80e4d2c0e197"
version = "2.3.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[deps.ArrayInterface]]
deps = ["Adapt", "LinearAlgebra", "Requires", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "bbec08a37f8722786d87bedf84eae19c020c4efa"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "7.7.0"

    [deps.ArrayInterface.extensions]
    ArrayInterfaceBandedMatricesExt = "BandedMatrices"
    ArrayInterfaceBlockBandedMatricesExt = "BlockBandedMatrices"
    ArrayInterfaceCUDAExt = "CUDA"
    ArrayInterfaceGPUArraysCoreExt = "GPUArraysCore"
    ArrayInterfaceStaticArraysCoreExt = "StaticArraysCore"
    ArrayInterfaceTrackerExt = "Tracker"

    [deps.ArrayInterface.weakdeps]
    BandedMatrices = "aae01518-5342-5314-be14-df237901396f"
    BlockBandedMatrices = "ffab5731-97b5-5995-9138-79e8c1846df0"
    CUDA = "052768ef-5323-5732-b1bb-66c8b64840ba"
    GPUArraysCore = "46192b85-c4d5-4398-a991-12ede77f4527"
    StaticArraysCore = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"

[[deps.ArrayLayouts]]
deps = ["FillArrays", "LinearAlgebra"]
git-tree-sha1 = "64d582bcb9c93ac741234789eeb4f16812413efb"
uuid = "4c555306-a7a7-4459-81d9-ec55ddd5c99a"
version = "1.6.0"
weakdeps = ["SparseArrays"]

    [deps.ArrayLayouts.extensions]
    ArrayLayoutsSparseArraysExt = "SparseArrays"

[[deps.Arrow_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Lz4_jll", "Pkg", "Thrift_jll", "Zlib_jll", "boost_jll", "snappy_jll"]
git-tree-sha1 = "d64cb60c0e6a138fbe5ea65bcbeea47813a9a700"
uuid = "8ce61222-c28f-5041-a97a-c2198fb817bf"
version = "10.0.0+1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Automa]]
deps = ["PrecompileTools", "TranscodingStreams"]
git-tree-sha1 = "588e0d680ad1d7201d4c6a804dcb1cd9cba79fbb"
uuid = "67c07d97-cdcb-5c2c-af73-a7f9c32a568b"
version = "1.0.3"

[[deps.AxisAlgorithms]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "WoodburyMatrices"]
git-tree-sha1 = "01b8ccb13d68535d73d2b0c23e39bd23155fb712"
uuid = "13072b0f-2c55-5437-9ae7-d433b7a33950"
version = "1.1.0"

[[deps.AxisArrays]]
deps = ["Dates", "IntervalSets", "IterTools", "RangeArrays"]
git-tree-sha1 = "16351be62963a67ac4083f748fdb3cca58bfd52f"
uuid = "39de3d68-74b9-583c-8d2d-e117c070f3a9"
version = "0.4.7"

[[deps.BangBang]]
deps = ["Accessors", "Compat", "ConstructionBase", "InitialValues", "LinearAlgebra", "Requires"]
git-tree-sha1 = "ffe3b6222215a9cf7ce449ad0b91274787a801c3"
uuid = "198e06fe-97b7-11e9-32a5-e1d131e6ad66"
version = "0.4.0"
weakdeps = ["ChainRulesCore", "DataFrames", "StaticArrays", "StructArrays", "Tables", "TypedTables"]

    [deps.BangBang.extensions]
    BangBangChainRulesCoreExt = "ChainRulesCore"
    BangBangDataFramesExt = "DataFrames"
    BangBangStaticArraysExt = "StaticArrays"
    BangBangStructArraysExt = "StructArrays"
    BangBangTablesExt = "Tables"
    BangBangTypedTablesExt = "TypedTables"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.Baselet]]
git-tree-sha1 = "aebf55e6d7795e02ca500a689d326ac979aaf89e"
uuid = "9718e550-a3fa-408a-8086-8db961cd8217"
version = "0.1.1"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "f1f03a9fa24271160ed7e73051fba3c1a759b53f"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.4.0"

[[deps.Bessels]]
git-tree-sha1 = "4435559dc39793d53a9e3d278e185e920b4619ef"
uuid = "0e736298-9ec6-45e8-9647-e4fc86a2fe38"
version = "0.2.8"

[[deps.BitIntegers]]
deps = ["Random"]
git-tree-sha1 = "a55462dfddabc34bc97d3a7403a2ca2802179ae6"
uuid = "c3b6d118-76ef-56ca-8cc7-ebb389d030a1"
version = "0.3.1"

[[deps.Blosc_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Lz4_jll", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "19b98ee7e3db3b4eff74c5c9c72bf32144e24f10"
uuid = "0b7ba130-8d10-5ba8-a3d6-c5182647fed9"
version = "1.21.5+0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9e2a6b69137e6969bab0152632dcb3bc108c8bdd"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+1"

[[deps.CEnum]]
git-tree-sha1 = "eb4cb44a499229b3b8426dcfb5dd85333951ff90"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.4.2"

[[deps.CFTime]]
deps = ["Dates", "Printf"]
git-tree-sha1 = "ed2e76c1c3c43fd9d0cb9248674620b29d71f2d1"
uuid = "179af706-886a-5703-950a-314cd64e0468"
version = "0.1.2"

[[deps.CRC32c]]
uuid = "8bf52ea8-c179-5cab-976a-9e18b702a9bc"

[[deps.CRlibm]]
deps = ["CRlibm_jll"]
git-tree-sha1 = "32abd86e3c2025db5172aa182b982debed519834"
uuid = "96374032-68de-5a5b-8d9e-752f78720389"
version = "1.0.1"

[[deps.CRlibm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e329286945d0cfc04456972ea732551869af1cfc"
uuid = "4e9b3aee-d8a1-5a3d-ad8b-7d824db253f0"
version = "1.0.1+0"

[[deps.CSV]]
deps = ["CodecZlib", "Dates", "FilePathsBase", "InlineStrings", "Mmap", "Parsers", "PooledArrays", "PrecompileTools", "SentinelArrays", "Tables", "Unicode", "WeakRefStrings", "WorkerUtilities"]
git-tree-sha1 = "679e69c611fff422038e9e21e270c4197d49d918"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.10.12"

[[deps.Cairo]]
deps = ["Cairo_jll", "Colors", "Glib_jll", "Graphics", "Libdl", "Pango_jll"]
git-tree-sha1 = "d0b3f8b4ad16cb0a2988c6788646a5e6a17b6b1b"
uuid = "159f3aea-2a34-519c-b102-8c37f9878175"
version = "1.0.5"

[[deps.CairoMakie]]
deps = ["CRC32c", "Cairo", "Colors", "FFTW", "FileIO", "FreeType", "GeometryBasics", "LinearAlgebra", "Makie", "PrecompileTools"]
git-tree-sha1 = "a80d49ed3333f5f78df8ffe76d07e88cc35e9172"
uuid = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
version = "0.11.8"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[deps.Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[deps.CategoricalArrays]]
deps = ["DataAPI", "Future", "Missings", "Printf", "Requires", "Statistics", "Unicode"]
git-tree-sha1 = "1568b28f91293458345dabba6a5ea3f183250a61"
uuid = "324d7699-5711-5eae-9e2f-1d82baa6b597"
version = "0.10.8"
weakdeps = ["JSON", "RecipesBase", "SentinelArrays", "StructTypes"]

    [deps.CategoricalArrays.extensions]
    CategoricalArraysJSONExt = "JSON"
    CategoricalArraysRecipesBaseExt = "RecipesBase"
    CategoricalArraysSentinelArraysExt = "SentinelArrays"
    CategoricalArraysStructTypesExt = "StructTypes"

[[deps.Chain]]
git-tree-sha1 = "8c4920235f6c561e401dfe569beb8b924adad003"
uuid = "8be319e6-bccf-4806-a6f7-6fae938471bc"
version = "0.5.0"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra"]
git-tree-sha1 = "ad25e7d21ce10e01de973cdc68ad0f850a953c52"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.21.1"
weakdeps = ["SparseArrays"]

    [deps.ChainRulesCore.extensions]
    ChainRulesCoreSparseArraysExt = "SparseArrays"

[[deps.CircularArrays]]
deps = ["OffsetArrays"]
git-tree-sha1 = "3f7b8a37359ae592cfa7aca7f811da045deff222"
uuid = "7a955b69-7140-5f4e-a0ed-f168c5e2e749"
version = "1.3.3"

[[deps.Clustering]]
deps = ["Distances", "LinearAlgebra", "NearestNeighbors", "Printf", "Random", "SparseArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "9ebb045901e9bbf58767a9f34ff89831ed711aae"
uuid = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
version = "0.15.7"

[[deps.CoDa]]
deps = ["AxisArrays", "Distances", "Distributions", "FillArrays", "LinearAlgebra", "Printf", "Random", "StaticArrays", "Statistics", "Tables"]
git-tree-sha1 = "0ae819d8911029b988479b8b447bf4fad4b5bfa7"
uuid = "5900dafe-f573-5c72-b367-76665857777b"
version = "1.4.0"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "9b1ca1aa6ce3f71b3d1840c538a8210a043625eb"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.8.2"

[[deps.CodecLz4]]
deps = ["Lz4_jll", "TranscodingStreams"]
git-tree-sha1 = "b8aecef9f90530cf322a8386630ec18485c17991"
uuid = "5ba52731-8f18-5e0d-9241-30f10d1ec561"
version = "0.4.3"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "59939d8a997469ee05c4b4944560a820f9ba0d73"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.4"

[[deps.CodecZstd]]
deps = ["TranscodingStreams", "Zstd_jll"]
git-tree-sha1 = "23373fecba848397b1705f6183188a0c0bc86917"
uuid = "6b39b394-51ab-5f42-8807-6242bab2b4c2"
version = "0.8.2"

[[deps.ColorBrewer]]
deps = ["Colors", "JSON", "Test"]
git-tree-sha1 = "61c5334f33d91e570e1d0c3eb5465835242582c4"
uuid = "a2cac450-b92f-5266-8821-25eda20663c8"
version = "0.4.0"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "PrecompileTools", "Random"]
git-tree-sha1 = "67c1f244b991cad9b0aa4b7540fb758c2488b129"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.24.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "Requires", "Statistics", "TensorCore"]
git-tree-sha1 = "a1f44953f2382ebb937d60dafbe2deea4bd23249"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.10.0"
weakdeps = ["SpecialFunctions"]

    [deps.ColorVectorSpace.extensions]
    SpecialFunctionsExt = "SpecialFunctions"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "fc08e5930ee9a4e03f84bfb5211cb54e7769758a"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.10"

[[deps.ColumnSelectors]]
git-tree-sha1 = "221157488d6e5942ef8cc53086cad651b632ed4e"
uuid = "9cc86067-7e36-4c61-b350-1ac9833d277f"
version = "0.1.1"

[[deps.Combinatorics]]
git-tree-sha1 = "08c8b6831dc00bfea825826be0bc8336fc369860"
uuid = "861a8166-3701-5b0c-9a16-15d98fcdc6aa"
version = "1.0.2"

[[deps.CommonDataModel]]
deps = ["CFTime", "DataStructures", "Dates", "Preferences", "Printf", "Statistics"]
git-tree-sha1 = "a132d267a055e8173a4a8e83d0d4ddcaeae70f91"
uuid = "1fbeeb36-5f17-413c-809b-666fb144f157"
version = "0.3.4"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "75bd5b6fc5089df449b5d35fa501c846c9b6549b"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.12.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.0+0"

[[deps.ComponentArrays]]
deps = ["ArrayInterface", "ChainRulesCore", "ForwardDiff", "Functors", "LinearAlgebra", "PackageExtensionCompat", "StaticArrayInterface", "StaticArraysCore"]
git-tree-sha1 = "871ddbe6da7d257a2fe983d427c1e8a37f8caaf8"
uuid = "b0b7db55-cfe3-40fc-9ded-d10e2dbeff66"
version = "0.15.8"

    [deps.ComponentArrays.extensions]
    ComponentArraysAdaptExt = "Adapt"
    ComponentArraysConstructionBaseExt = "ConstructionBase"
    ComponentArraysGPUArraysExt = "GPUArrays"
    ComponentArraysRecursiveArrayToolsExt = "RecursiveArrayTools"
    ComponentArraysReverseDiffExt = "ReverseDiff"
    ComponentArraysSciMLBaseExt = "SciMLBase"
    ComponentArraysTrackerExt = "Tracker"
    ComponentArraysZygoteExt = "Zygote"

    [deps.ComponentArrays.weakdeps]
    Adapt = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
    ConstructionBase = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
    GPUArrays = "0c68f7d7-f131-5f86-a1c3-88cf8149b2d7"
    RecursiveArrayTools = "731186ca-8d62-57ce-b412-fbd966d074cd"
    ReverseDiff = "37e2e3b7-166d-5795-8a7a-e32c996b4267"
    SciMLBase = "0bca4576-84f4-4d90-8ffe-ffa030f20462"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"
    Zygote = "e88e6eb3-aa80-5325-afca-941959d7151f"

[[deps.CompositionsBase]]
git-tree-sha1 = "802bb88cd69dfd1509f6670416bd4434015693ad"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.2"
weakdeps = ["InverseFunctions"]

    [deps.CompositionsBase.extensions]
    CompositionsBaseInverseFunctionsExt = "InverseFunctions"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "c53fc348ca4d40d7b371e71fd52251839080cbc9"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.4"
weakdeps = ["IntervalSets", "StaticArrays"]

    [deps.ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseStaticArraysExt = "StaticArrays"

[[deps.Contour]]
git-tree-sha1 = "d05d9e7b7aedff4e5b51a029dced05cfb6125781"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.2"

[[deps.CoordinateTransformations]]
deps = ["LinearAlgebra", "StaticArrays"]
git-tree-sha1 = "f9d7112bfff8a19a3a4ea4e03a8e6a91fe8456bf"
uuid = "150eb455-5306-5404-9cee-2592286d6298"
version = "0.6.3"

[[deps.CpuId]]
deps = ["Markdown"]
git-tree-sha1 = "fcbb72b032692610bfbdb15018ac16a36cf2e406"
uuid = "adafc99b-e345-5852-983c-f28acb93d879"
version = "0.3.1"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DBFTables]]
deps = ["Dates", "Printf", "Tables", "WeakRefStrings"]
git-tree-sha1 = "971a159c2ad2624dd86fff9ec39eea6d602170cd"
uuid = "75c7ada1-017a-5fb6-b8c7-2125ff2d6c93"
version = "1.2.4"

[[deps.DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "DataStructures", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrecompileTools", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SentinelArrays", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "04c738083f29f86e62c8afc341f0967d8717bdb8"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.6.1"

[[deps.DataScienceTraits]]
deps = ["Dates"]
git-tree-sha1 = "166d104f4141418da04c87fef740a0ec526fb060"
uuid = "6cb2f572-2d2b-4ba6-bdb3-e710fa044d6c"
version = "0.2.4"

    [deps.DataScienceTraits.extensions]
    DataScienceTraitsCategoricalArraysExt = "CategoricalArrays"
    DataScienceTraitsCoDaExt = "CoDa"
    DataScienceTraitsDistributionsExt = "Distributions"
    DataScienceTraitsDynamicQuantitiesExt = "DynamicQuantities"
    DataScienceTraitsMeshesExt = "Meshes"
    DataScienceTraitsUnitfulExt = "Unitful"

    [deps.DataScienceTraits.weakdeps]
    CategoricalArrays = "324d7699-5711-5eae-9e2f-1d82baa6b597"
    CoDa = "5900dafe-f573-5c72-b367-76665857777b"
    Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
    DynamicQuantities = "06fc5a27-2a28-4c7c-a15d-362465fb6821"
    Meshes = "eacbb407-ea5a-433e-ab97-5258b1ca43fa"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "ac67408d9ddf207de5cfa9a97e114352430f01ed"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.16"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DecFP]]
deps = ["DecFP_jll", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "4a10cec664e26d9d63597daf9e62147e79d636e3"
uuid = "55939f99-70c6-5e9b-8bb0-5071ed7d61fd"
version = "1.3.2"

[[deps.DecFP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e9a8da19f847bbfed4076071f6fef8665a30d9e5"
uuid = "47200ebd-12ce-5be5-abb7-8e082af23329"
version = "2.0.3+1"

[[deps.DecisionTree]]
deps = ["AbstractTrees", "DelimitedFiles", "LinearAlgebra", "Random", "ScikitLearnBase", "Statistics"]
git-tree-sha1 = "526ca14aaaf2d5a0e242f3a8a7966eb9065d7d78"
uuid = "7806a523-6efd-50cb-b5f6-3fa6f1930dbb"
version = "0.12.4"

[[deps.DefineSingletons]]
git-tree-sha1 = "0fba8b706d0178b4dc7fd44a96a92382c9065c2c"
uuid = "244e2a9f-e319-4986-a169-4d1fe445cd52"
version = "0.1.2"

[[deps.DelaunayTriangulation]]
deps = ["DataStructures", "EnumX", "ExactPredicates", "Random", "SimpleGraphs"]
git-tree-sha1 = "d4e9dc4c6106b8d44e40cd4faf8261a678552c7c"
uuid = "927a84f5-c5f4-47a5-9785-b46e178433df"
version = "0.8.12"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.DensityRatioEstimation]]
deps = ["LinearAlgebra", "Parameters", "Random", "Statistics", "StatsBase"]
git-tree-sha1 = "1a22dc9baf8d0b2849c5b053b4f353727581fccf"
uuid = "ab46fb84-d57c-11e9-2f65-6f72e4a7229f"
version = "1.2.1"

    [deps.DensityRatioEstimation.extensions]
    DensityRatioEstimationChainRulesCoreExt = "ChainRulesCore"
    DensityRatioEstimationConvexExt = ["Convex", "ECOS"]
    DensityRatioEstimationGPUArraysExt = "GPUArrays"
    DensityRatioEstimationJuMPExt = ["JuMP", "Ipopt"]
    DensityRatioEstimationOptimExt = "Optim"

    [deps.DensityRatioEstimation.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Convex = "f65535da-76fb-5f13-bab9-19810c17039a"
    ECOS = "e2685f51-7e38-5353-a97d-a921fd2c8199"
    GPUArrays = "0c68f7d7-f131-5f86-a1c3-88cf8149b2d7"
    Ipopt = "b6b21f68-93f8-5de0-b562-5493be1d77c9"
    JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
    Optim = "429524aa-4258-5aef-a3af-852621145aeb"

[[deps.Dictionaries]]
deps = ["Indexing", "Random", "Serialization"]
git-tree-sha1 = "573c92ef22ee0783bfaa4007c732b044c791bc6d"
uuid = "85a47980-9c8c-11e8-2b9f-f7ca1fa99fb4"
version = "0.4.1"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "23163d55f885173722d1e4cf0f6110cdbaf7e272"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.15.1"

[[deps.DiskArrays]]
deps = ["LRUCache", "OffsetArrays"]
git-tree-sha1 = "ef25c513cad08d7ebbed158c91768ae32f308336"
uuid = "3c3547ce-8d99-4f5e-a174-61eb10b00ae3"
version = "0.3.23"

[[deps.Distances]]
deps = ["LinearAlgebra", "Statistics", "StatsAPI"]
git-tree-sha1 = "66c4c81f259586e8f002eacebc177e1fb06363b0"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.11"
weakdeps = ["ChainRulesCore", "SparseArrays"]

    [deps.Distances.extensions]
    DistancesChainRulesCoreExt = "ChainRulesCore"
    DistancesSparseArraysExt = "SparseArrays"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Distributions]]
deps = ["FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SpecialFunctions", "Statistics", "StatsAPI", "StatsBase", "StatsFuns"]
git-tree-sha1 = "7c302d7a5fec5214eb8a5a4c466dcf7a51fcf169"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.107"

    [deps.Distributions.extensions]
    DistributionsChainRulesCoreExt = "ChainRulesCore"
    DistributionsDensityInterfaceExt = "DensityInterface"
    DistributionsTestExt = "Test"

    [deps.Distributions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DensityInterface = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
    Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.DualNumbers]]
deps = ["Calculus", "NaNMath", "SpecialFunctions"]
git-tree-sha1 = "5837a837389fccf076445fce071c8ddaea35a566"
uuid = "fa6b7ba4-c1ee-5f82-b5fc-ecf0adba8f74"
version = "0.6.8"

[[deps.EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e3290f2d49e661fbd94046d7e3726ffcb2d41053"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.4+0"

[[deps.EnumX]]
git-tree-sha1 = "bdb1942cd4c45e3c678fd11569d5cccd80976237"
uuid = "4e289a0a-7415-4d19-859d-a7e5c4648b56"
version = "1.0.4"

[[deps.ExactPredicates]]
deps = ["IntervalArithmetic", "Random", "StaticArrays"]
git-tree-sha1 = "b3f2ff58735b5f024c392fde763f29b057e4b025"
uuid = "429591f6-91af-11e9-00e2-59fbe8cec110"
version = "2.2.8"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "4558ab818dcceaab612d1bb8c19cee87eda2b83c"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.5.0+0"

[[deps.Extents]]
git-tree-sha1 = "2140cd04483da90b2da7f99b2add0750504fc39c"
uuid = "411431e0-e8b7-467b-b5e0-f676ba4f2910"
version = "0.1.2"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "466d45dc38e15794ec7d5d63ec03d776a9aff36e"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.4+1"

[[deps.FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "4820348781ae578893311153d69049a93d05f39d"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.8.0"

[[deps.FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[deps.FNVHash]]
git-tree-sha1 = "d6de2c735a8bffce9bc481942dfa453cc815357e"
uuid = "5207ad80-27db-4d23-8732-fa0bd339ea89"
version = "0.1.0"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "c5c28c245101bd59154f649e19b038d15901b5dc"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.2"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "9f00e42f8d99fdde64d40c8ea5d14269a2e2c1aa"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.21"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FillArrays]]
deps = ["LinearAlgebra", "Random"]
git-tree-sha1 = "5b93957f6dcd33fc343044af3d48c215be2562f1"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "1.9.3"
weakdeps = ["PDMats", "SparseArrays", "Statistics"]

    [deps.FillArrays.extensions]
    FillArraysPDMatsExt = "PDMats"
    FillArraysSparseArraysExt = "SparseArrays"
    FillArraysStatisticsExt = "Statistics"

[[deps.FiniteDiff]]
deps = ["ArrayInterface", "LinearAlgebra", "Requires", "Setfield", "SparseArrays"]
git-tree-sha1 = "73d1214fec245096717847c62d389a5d2ac86504"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.22.0"

    [deps.FiniteDiff.extensions]
    FiniteDiffBandedMatricesExt = "BandedMatrices"
    FiniteDiffBlockBandedMatricesExt = "BlockBandedMatrices"
    FiniteDiffStaticArraysExt = "StaticArrays"

    [deps.FiniteDiff.weakdeps]
    BandedMatrices = "aae01518-5342-5314-be14-df237901396f"
    BlockBandedMatrices = "ffab5731-97b5-5995-9138-79e8c1846df0"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "cf0fe81336da9fb90944683b8c41984b08793dad"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.36"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[deps.FreeType]]
deps = ["CEnum", "FreeType2_jll"]
git-tree-sha1 = "907369da0f8e80728ab49c1c7e09327bf0d6d999"
uuid = "b38be410-82b0-50bf-ab77-7b57e271db43"
version = "4.1.1"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "d8db6a5a2fe1381c1ea4ef2cab7c69c2de7f9ea0"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.13.1+0"

[[deps.FreeTypeAbstraction]]
deps = ["ColorVectorSpace", "Colors", "FreeType", "GeometryBasics"]
git-tree-sha1 = "055626e1a35f6771fe99060e835b72ca61a52621"
uuid = "663a7486-cb36-511b-a19d-713bb74d65c9"
version = "0.10.1"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.Functors]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "166c544477f97bbadc7179ede1c1868e0e9b426b"
uuid = "d9f16b24-f501-4c13-a1f2-28368ffc5196"
version = "0.4.7"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GDAL]]
deps = ["CEnum", "GDAL_jll", "NetworkOptions", "PROJ_jll"]
git-tree-sha1 = "50bfa3f63b47ed1873c35f7fea19893a288f6785"
uuid = "add2ef01-049f-52c4-9ee2-e494f65e021a"
version = "1.7.1"

[[deps.GDAL_jll]]
deps = ["Arrow_jll", "Artifacts", "Expat_jll", "GEOS_jll", "HDF5_jll", "JLLWrappers", "LibCURL_jll", "LibPQ_jll", "Libdl", "Libtiff_jll", "NetCDF_jll", "OpenJpeg_jll", "PROJ_jll", "SQLite_jll", "Zlib_jll", "Zstd_jll", "libgeotiff_jll"]
git-tree-sha1 = "f0d160a50c63520db7b8775e26365f1057381235"
uuid = "a7073274-a066-55f0-b90d-d619367d196c"
version = "301.800.300+0"

[[deps.GEOS_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e143352a8a1b1c7236d05bc9e0982420099c46af"
uuid = "d604d12d-fa86-5845-992e-78dc15976526"
version = "3.12.0+0"

[[deps.GLM]]
deps = ["Distributions", "LinearAlgebra", "Printf", "Reexport", "SparseArrays", "SpecialFunctions", "Statistics", "StatsAPI", "StatsBase", "StatsFuns", "StatsModels"]
git-tree-sha1 = "273bd1cd30768a2fddfa3fd63bbc746ed7249e5f"
uuid = "38e38edf-8417-5370-95a0-9cbb8c7f171a"
version = "1.9.0"

[[deps.GMP_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "781609d7-10c4-51f6-84f2-b8444358ff6d"
version = "6.2.1+6"

[[deps.GPUArraysCore]]
deps = ["Adapt"]
git-tree-sha1 = "ec632f177c0d990e64d955ccc1b8c04c485a0950"
uuid = "46192b85-c4d5-4398-a991-12ede77f4527"
version = "0.1.6"

[[deps.GRIB]]
deps = ["eccodes_jll"]
git-tree-sha1 = "e4818470ebb3282e2c720fa4484e2b133cdef6d3"
uuid = "b16dfd50-4035-11e9-28d4-9dfe17e6779b"
version = "0.4.0"

[[deps.GRIBDatasets]]
deps = ["CommonDataModel", "DataStructures", "Dates", "DiskArrays", "GRIB"]
git-tree-sha1 = "11ed757183a4d6651c6c494fe475b92a2ea64b2a"
uuid = "82be9cdb-ee19-4151-bdb3-b400788d9abc"
version = "0.3.1"

[[deps.GeoFormatTypes]]
git-tree-sha1 = "59107c179a586f0fe667024c5eb7033e81333271"
uuid = "68eda718-8dee-11e9-39e7-89f7f65f511f"
version = "0.4.2"

[[deps.GeoIO]]
deps = ["ArchGDAL", "CSV", "Colors", "CommonDataModel", "FileIO", "Formatting", "GRIBDatasets", "GeoInterface", "GeoJSON", "GeoParquet", "GeoTables", "GslibIO", "ImageIO", "Meshes", "NCDatasets", "PlyIO", "PrecompileTools", "PrettyTables", "ReadVTK", "Rotations", "Shapefile", "StaticArrays", "Tables", "TransformsBase", "VTKBase", "WriteVTK"]
git-tree-sha1 = "79a60925795c61ee940dea06368664e363707a2a"
uuid = "f5a160d5-e41d-4189-8b61-d57781c419e3"
version = "1.12.7"

[[deps.GeoInterface]]
deps = ["Extents"]
git-tree-sha1 = "d4f85701f569584f2cff7ba67a137d03f0cfb7d0"
uuid = "cf35fbd7-0cd7-5166-be24-54bfbe79505f"
version = "1.3.3"

[[deps.GeoInterfaceMakie]]
deps = ["GeoInterface", "GeometryBasics", "MakieCore"]
git-tree-sha1 = "c15f793d501789ffa1cd171103406573d00f71cc"
uuid = "0edc0954-3250-4c18-859d-ec71c1660c08"
version = "0.1.5"

[[deps.GeoInterfaceRecipes]]
deps = ["GeoInterface", "RecipesBase"]
git-tree-sha1 = "fb1156076f24f1dfee45b3feadb31d05730a49ac"
uuid = "0329782f-3d07-4b52-b9f6-d3137cf03c7a"
version = "1.0.2"

[[deps.GeoJSON]]
deps = ["Extents", "GeoFormatTypes", "GeoInterface", "GeoInterfaceMakie", "GeoInterfaceRecipes", "JSON3", "StructTypes", "Tables"]
git-tree-sha1 = "5846df44b97b4af377fd057b3a2a393228081a3c"
uuid = "61d90e0f-e114-555e-ac52-39dfb47a3ef9"
version = "0.8.0"
weakdeps = ["Makie"]

    [deps.GeoJSON.extensions]
    GeoJSONMakieExt = "Makie"

[[deps.GeoParquet]]
deps = ["DataFrames", "Extents", "GeoFormatTypes", "GeoInterface", "JSON3", "Parquet2", "StructTypes", "Tables", "WellKnownGeometry"]
git-tree-sha1 = "b0b2d79d58420ec01260fc78bc2f1f8ec8192322"
uuid = "e99870d8-ce00-4fdd-aeee-e09192881159"
version = "0.2.1"

[[deps.GeoStats]]
deps = ["CategoricalArrays", "Chain", "CoDa", "DataScienceTraits", "Dates", "DensityRatioEstimation", "Distances", "Distributions", "GeoStatsBase", "GeoStatsFunctions", "GeoStatsModels", "GeoStatsProcesses", "GeoStatsTransforms", "GeoStatsValidation", "GeoTables", "LossFunctions", "Meshes", "Reexport", "Rotations", "Statistics", "StatsLearnModels", "TableTransforms", "Tables", "Unitful"]
git-tree-sha1 = "7beb278484cbd615e003daaeca3267ffc84890d6"
uuid = "dcc97b0b-8ce5-5539-9008-bb190f959ef6"
version = "0.51.0"

[[deps.GeoStatsBase]]
deps = ["CategoricalArrays", "ColumnSelectors", "DataScienceTraits", "DensityRatioEstimation", "Distances", "GeoTables", "LinearAlgebra", "Meshes", "Optim", "Rotations", "StaticArrays", "Statistics", "StatsBase", "Tables", "TypedTables"]
git-tree-sha1 = "4a03136e18a5a77be92cd717606a67b514603fe1"
uuid = "323cb8eb-fbf6-51c0-afd0-f8fba70507b2"
version = "0.43.7"
weakdeps = ["Makie"]

    [deps.GeoStatsBase.extensions]
    GeoStatsBaseMakieExt = "Makie"

[[deps.GeoStatsFunctions]]
deps = ["Bessels", "Distances", "GeoTables", "InteractiveUtils", "LinearAlgebra", "Meshes", "NearestNeighbors", "Optim", "Printf", "Random", "Setfield", "Statistics", "Tables", "Transducers", "Unitful"]
git-tree-sha1 = "d2e889ac30310d8487dfb3944543655092f443b0"
uuid = "6771c435-bc22-4842-b0c3-41852a255103"
version = "0.1.2"
weakdeps = ["Makie"]

    [deps.GeoStatsFunctions.extensions]
    GeoStatsFunctionsMakieExt = "Makie"

[[deps.GeoStatsModels]]
deps = ["Combinatorics", "Distances", "Distributions", "GeoStatsFunctions", "GeoTables", "LinearAlgebra", "Meshes", "Statistics", "Tables", "Unitful"]
git-tree-sha1 = "0083352204fd14fe38847e739166da0571562644"
uuid = "ad987403-13c5-47b5-afee-0a48f6ac4f12"
version = "0.3.0"

[[deps.GeoStatsProcesses]]
deps = ["Bessels", "CpuId", "Distances", "Distributed", "Distributions", "FFTW", "GeoStatsBase", "GeoStatsFunctions", "GeoStatsModels", "GeoTables", "LinearAlgebra", "Meshes", "ProgressMeter", "Random", "Statistics", "Tables"]
git-tree-sha1 = "6eaed2e884115518b8bf7410cf798e97000dcccd"
uuid = "aa102bde-5a27-4b0c-b2c1-e7a7dcc4c3e7"
version = "0.5.1"

    [deps.GeoStatsProcesses.extensions]
    GeoStatsProcessesImageQuiltingExt = "ImageQuilting"
    GeoStatsProcessesStratiGraphicsExt = "StratiGraphics"
    GeoStatsProcessesTuringPatternsExt = "TuringPatterns"

    [deps.GeoStatsProcesses.weakdeps]
    ImageQuilting = "e8712464-036d-575c-85ac-952ae31322ab"
    StratiGraphics = "135379e1-83be-5ae7-9e8e-29dade3dc6c7"
    TuringPatterns = "fde5428d-3bf0-5ade-b94a-d334303c4d77"

[[deps.GeoStatsTransforms]]
deps = ["ArnoldiMethod", "CategoricalArrays", "Clustering", "ColumnSelectors", "Combinatorics", "DataScienceTraits", "Distances", "GeoStatsModels", "GeoStatsProcesses", "GeoTables", "LinearAlgebra", "Meshes", "Random", "SparseArrays", "Statistics", "TableDistances", "TableTransforms", "Tables", "Unitful"]
git-tree-sha1 = "8582fec07d3542ebba4da1e4c26fc416eebead86"
uuid = "725d9659-360f-4996-9c94-5f19c7e4a8a6"
version = "0.3.2"

[[deps.GeoStatsValidation]]
deps = ["ColumnSelectors", "DataScienceTraits", "DensityRatioEstimation", "GeoStatsBase", "GeoStatsModels", "GeoStatsTransforms", "GeoTables", "LossFunctions", "Meshes", "StatsLearnModels", "Transducers"]
git-tree-sha1 = "c070722968dc8ea61305c292e33bd45d06ae6ff6"
uuid = "36f43c0d-3673-45fc-9557-6860e708e7aa"
version = "0.2.0"

[[deps.GeoTables]]
deps = ["CategoricalArrays", "ColumnSelectors", "DataAPI", "DataScienceTraits", "Dates", "Distributions", "Meshes", "PrettyTables", "Random", "Statistics", "Tables", "Unitful"]
git-tree-sha1 = "a38188e01d58df62dd4beeb504c03b4ad7653039"
uuid = "e502b557-6362-48c1-8219-d30d308dcdb0"
version = "1.17.0"
weakdeps = ["Makie", "TableTransforms"]

    [deps.GeoTables.extensions]
    GeoTablesMakieExt = "Makie"
    GeoTablesTableTransformsExt = "TableTransforms"

[[deps.GeometryBasics]]
deps = ["EarCut_jll", "Extents", "GeoInterface", "IterTools", "LinearAlgebra", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "5694b56ccf9d15addedc35e9a4ba9c317721b788"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.4.10"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Zlib_jll"]
git-tree-sha1 = "e94c92c7bf4819685eb80186d51c43e71d4afa17"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.76.5+0"

[[deps.GnuTLS_jll]]
deps = ["Artifacts", "GMP_jll", "JLLWrappers", "Libdl", "Nettle_jll", "P11Kit_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "266fe9b2335527cbf569ba4fd0979e3d8c6fd491"
uuid = "0951126a-58fd-58f1-b5b3-b08c7c4a876d"
version = "3.7.8+1"

[[deps.Graphics]]
deps = ["Colors", "LinearAlgebra", "NaNMath"]
git-tree-sha1 = "d61890399bc535850c4bf08e4e0d3a7ad0f21cbd"
uuid = "a2bd30eb-e257-5431-a919-1863eab51364"
version = "1.1.2"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.GridLayoutBase]]
deps = ["GeometryBasics", "InteractiveUtils", "Observables"]
git-tree-sha1 = "af13a277efd8a6e716d79ef635d5342ccb75be61"
uuid = "3955a311-db13-416c-9275-1d80ed98e5e9"
version = "0.10.0"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.GslibIO]]
deps = ["DelimitedFiles", "GeoTables", "Meshes", "Printf", "Tables"]
git-tree-sha1 = "74fdadeef172c8506f0e2a574ab07a8971110b85"
uuid = "4610876b-9b01-57c8-9ad9-06315f1a66a5"
version = "1.4.8"

[[deps.HDF5_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LazyArtifacts", "LibCURL_jll", "Libdl", "MPICH_jll", "MPIPreferences", "MPItrampoline_jll", "MicrosoftMPI_jll", "OpenMPI_jll", "OpenSSL_jll", "TOML", "Zlib_jll", "libaec_jll"]
git-tree-sha1 = "e4591176488495bf44d7456bd73179d87d5e6eab"
uuid = "0234f1f7-429e-5d53-9886-15a909be8d59"
version = "1.14.3+1"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[deps.HypergeometricFunctions]]
deps = ["DualNumbers", "LinearAlgebra", "OpenLibm_jll", "SpecialFunctions"]
git-tree-sha1 = "f218fe3736ddf977e0e772bc9a586b2383da2685"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.23"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "7134810b1afce04bbc1045ca1985fbe81ce17653"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.5"

[[deps.ICU_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "20b6765a3016e1fca0c9c93c80d50061b94218b7"
uuid = "a51ab1cf-af8e-5615-a023-bc2c838bba6b"
version = "69.1.0+0"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "8b72179abc660bfab5e28472e019392b97d0985c"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.4"

[[deps.IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[deps.ImageAxes]]
deps = ["AxisArrays", "ImageBase", "ImageCore", "Reexport", "SimpleTraits"]
git-tree-sha1 = "2e4520d67b0cef90865b3ef727594d2a58e0e1f8"
uuid = "2803e5a7-5153-5ecf-9a86-9b4c37f5f5ac"
version = "0.6.11"

[[deps.ImageBase]]
deps = ["ImageCore", "Reexport"]
git-tree-sha1 = "eb49b82c172811fd2c86759fa0553a2221feb909"
uuid = "c817782e-172a-44cc-b673-b171935fbb9e"
version = "0.1.7"

[[deps.ImageCore]]
deps = ["ColorVectorSpace", "Colors", "FixedPointNumbers", "MappedArrays", "MosaicViews", "OffsetArrays", "PaddedViews", "PrecompileTools", "Reexport"]
git-tree-sha1 = "b2a7eaa169c13f5bcae8131a83bc30eff8f71be0"
uuid = "a09fc81d-aa75-5fe9-8630-4744c3626534"
version = "0.10.2"

[[deps.ImageIO]]
deps = ["FileIO", "IndirectArrays", "JpegTurbo", "LazyModules", "Netpbm", "OpenEXR", "PNGFiles", "QOI", "Sixel", "TiffImages", "UUIDs"]
git-tree-sha1 = "bca20b2f5d00c4fbc192c3212da8fa79f4688009"
uuid = "82e4d734-157c-48bb-816b-45c225c6df19"
version = "0.6.7"

[[deps.ImageMetadata]]
deps = ["AxisArrays", "ImageAxes", "ImageBase", "ImageCore"]
git-tree-sha1 = "355e2b974f2e3212a75dfb60519de21361ad3cb7"
uuid = "bc367c6b-8a6b-528e-b4bd-a4b897500b49"
version = "0.9.9"

[[deps.Imath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "3d09a9f60edf77f8a4d99f9e015e8fbf9989605d"
uuid = "905a6f67-0a94-5f89-b386-d35d92009cd1"
version = "3.1.7+0"

[[deps.Indexing]]
git-tree-sha1 = "ce1566720fd6b19ff3411404d4b977acd4814f9f"
uuid = "313cdc1a-70c2-5d6a-ae34-0150d3930a38"
version = "1.1.1"

[[deps.IndirectArrays]]
git-tree-sha1 = "012e604e1c7458645cb8b436f8fba789a51b257f"
uuid = "9b13fd28-a010-5f03-acff-a1bbcff69959"
version = "1.0.0"

[[deps.Inflate]]
git-tree-sha1 = "ea8031dea4aff6bd41f1df8f2fdfb25b33626381"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.4"

[[deps.InitialValues]]
git-tree-sha1 = "4da0f88e9a39111c2fa3add390ab15f3a44f3ca3"
uuid = "22cec73e-a1b8-11e9-2c92-598750a2cf9c"
version = "0.3.1"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.IntegerMathUtils]]
git-tree-sha1 = "b8ffb903da9f7b8cf695a8bead8e01814aa24b30"
uuid = "18e54dd8-cb9d-406c-a71d-865a43cbb235"
version = "0.1.2"

[[deps.IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "5fdf2fe6724d8caabf43b557b84ce53f3b7e2f6b"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2024.0.2+0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.Interpolations]]
deps = ["Adapt", "AxisAlgorithms", "ChainRulesCore", "LinearAlgebra", "OffsetArrays", "Random", "Ratios", "Requires", "SharedArrays", "SparseArrays", "StaticArrays", "WoodburyMatrices"]
git-tree-sha1 = "88a101217d7cb38a7b481ccd50d21876e1d1b0e0"
uuid = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
version = "0.15.1"
weakdeps = ["Unitful"]

    [deps.Interpolations.extensions]
    InterpolationsUnitfulExt = "Unitful"

[[deps.IntervalArithmetic]]
deps = ["CRlibm", "RoundingEmulator"]
git-tree-sha1 = "c274ec586ea58eb7b42afd0c5d67e50ff50229b5"
uuid = "d1acc4aa-44c8-5952-acd4-ba5d80a2a253"
version = "0.22.5"
weakdeps = ["DiffRules", "RecipesBase"]

    [deps.IntervalArithmetic.extensions]
    IntervalArithmeticDiffRulesExt = "DiffRules"
    IntervalArithmeticRecipesBaseExt = "RecipesBase"

[[deps.IntervalSets]]
git-tree-sha1 = "581191b15bcb56a2aa257e9c160085d0f128a380"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.7.9"
weakdeps = ["Random", "Statistics"]

    [deps.IntervalSets.extensions]
    IntervalSetsRandomExt = "Random"
    IntervalSetsStatisticsExt = "Statistics"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "68772f49f54b479fa88ace904f6127f0a3bb2e46"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.12"

[[deps.InvertedIndices]]
git-tree-sha1 = "0dc7b50b8d436461be01300fd8cd45aa0274b038"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.Isoband]]
deps = ["isoband_jll"]
git-tree-sha1 = "f9b6d97355599074dc867318950adaa6f9946137"
uuid = "f1662d9f-8043-43de-a69a-05efc1cc6ff4"
version = "0.1.1"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7e5d6779a1e09a36db2a7b6cff50942a0a7d0fca"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.5.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "PrecompileTools", "StructTypes", "UUIDs"]
git-tree-sha1 = "eb3edce0ed4fa32f75a0a11217433c31d56bd48b"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.14.0"

    [deps.JSON3.extensions]
    JSON3ArrowExt = ["ArrowTypes"]

    [deps.JSON3.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JpegTurbo]]
deps = ["CEnum", "FileIO", "ImageCore", "JpegTurbo_jll", "TOML"]
git-tree-sha1 = "fa6d0bcff8583bac20f1ffa708c3913ca605c611"
uuid = "b835a17e-a41a-41e7-81f0-2f016b05efe0"
version = "0.1.5"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "60b1194df0a3298f460063de985eae7b01bc011a"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "3.0.1+0"

[[deps.Kerberos_krb5_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "60274b4ab38e8d1248216fe6b6ace75ae09b0502"
uuid = "b39eb1a6-c29a-53d7-8c32-632cd16f18da"
version = "1.19.3+0"

[[deps.KernelDensity]]
deps = ["Distributions", "DocStringExtensions", "FFTW", "Interpolations", "StatsBase"]
git-tree-sha1 = "fee018a29b60733876eb557804b5b109dd3dd8a7"
uuid = "5ab0869b-81aa-558d-bb23-cbf5423bbe9b"
version = "0.6.8"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[deps.LLVMOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "d986ce2d884d49126836ea94ed5bfb0f12679713"
uuid = "1d63c593-3942-5779-bab2-d838dc0a180e"
version = "15.0.7+0"

[[deps.LRUCache]]
git-tree-sha1 = "b3cc6698599b10e652832c2f23db3cab99d51b59"
uuid = "8ac3fa9e-de4c-5943-b1dc-09c6b5f20637"
version = "1.6.1"
weakdeps = ["Serialization"]

    [deps.LRUCache.extensions]
    SerializationExt = ["Serialization"]

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "50901ebc375ed41dbf8058da26f9de442febbbec"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.1"

[[deps.LazyArrays]]
deps = ["ArrayLayouts", "FillArrays", "LinearAlgebra", "MacroTools", "MatrixFactorizations", "SparseArrays"]
git-tree-sha1 = "9cfca23ab83b0dfac93cb1a1ef3331ab9fe596a5"
uuid = "5078a376-72f3-5289-bfd5-ec5146d43c02"
version = "1.8.3"
weakdeps = ["StaticArrays"]

    [deps.LazyArrays.extensions]
    LazyArraysStaticArraysExt = "StaticArrays"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LazyModules]]
git-tree-sha1 = "a560dd966b386ac9ae60bdd3a3d3a326062d3c3e"
uuid = "8cdb02fc-e678-4876-92c5-9defec4f444e"
version = "0.3.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.4.0+0"

[[deps.LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.6.4+0"

[[deps.LibPQ_jll]]
deps = ["Artifacts", "ICU_jll", "JLLWrappers", "Kerberos_krb5_jll", "Libdl", "OpenSSL_jll", "Zstd_jll"]
git-tree-sha1 = "09163f837936c8cc44f4691cb41d805eb1769642"
uuid = "08be9ffa-1c94-5ee5-a977-46a84ec9b350"
version = "16.0.0+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "f9557a255370125b405568f9767d6d195822a175"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.17.0+0"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "XZ_jll", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "2da088d113af58221c52828a80378e16be7d037a"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.5.1+1"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LightBSON]]
deps = ["DataStructures", "Dates", "DecFP", "FNVHash", "JSON3", "Sockets", "StructTypes", "Transducers", "UUIDs", "UnsafeArrays", "WeakRefStrings"]
git-tree-sha1 = "d4d5cc8209c57ad04b35071da39ee8a006a0d938"
uuid = "a4a7f996-b3a6-4de6-b9db-2fa5f350df41"
version = "0.2.17"

[[deps.LightXML]]
deps = ["Libdl", "XML2_jll"]
git-tree-sha1 = "3a994404d3f6709610701c7dabfc03fed87a81f8"
uuid = "9c8b4983-aa76-5018-a973-4c85ecc9e179"
version = "0.9.1"

[[deps.LineSearches]]
deps = ["LinearAlgebra", "NLSolversBase", "NaNMath", "Parameters", "Printf"]
git-tree-sha1 = "7bbea35cec17305fc70a0e5b4641477dc0789d9d"
uuid = "d3d80556-e9d4-5f37-9878-2ab0fcc64255"
version = "7.2.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LinearAlgebraX]]
deps = ["LinearAlgebra", "Mods", "Primes", "SimplePolynomials"]
git-tree-sha1 = "d76cec8007ec123c2b681269d40f94b053473fcf"
uuid = "9b3f67b0-2d00-526e-9884-9e4938f8fb88"
version = "0.2.7"

[[deps.LittleCMS_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll"]
git-tree-sha1 = "08ed30575ffc5651a50d3291beaf94c3e7996e55"
uuid = "d3a379c0-f9a3-5b72-a4c0-6bf4d2e8af0f"
version = "2.15.0+0"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "7d6dd4e9212aebaeed356de34ccf262a3cd415aa"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.26"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LossFunctions]]
deps = ["Markdown", "Requires", "Statistics"]
git-tree-sha1 = "df9da07efb9b05ca7ef701acec891ee8f73c99e2"
uuid = "30fc2ffe-d236-52d8-8643-a9d8f7c094a7"
version = "0.11.1"
weakdeps = ["CategoricalArrays"]

    [deps.LossFunctions.extensions]
    LossFunctionsCategoricalArraysExt = "CategoricalArrays"

[[deps.Lz4_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6c26c5e8a4203d43b5497be3ec5d4e0c3cde240a"
uuid = "5ced341a-0733-55b8-9ab6-a4889d929147"
version = "1.9.4+0"

[[deps.MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

[[deps.MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl"]
git-tree-sha1 = "72dc3cf284559eb8f53aa593fe62cb33f83ed0c0"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2024.0.0+0"

[[deps.MPICH_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "MPIPreferences", "TOML"]
git-tree-sha1 = "2ee75365ca243c1a39d467e35ffd3d4d32eef11e"
uuid = "7cb0a576-ebde-5e09-9194-50597f1243b4"
version = "4.1.2+1"

[[deps.MPIPreferences]]
deps = ["Libdl", "Preferences"]
git-tree-sha1 = "8f6af051b9e8ec597fa09d8885ed79fd582f33c9"
uuid = "3da0fdf6-3ccc-4f1b-acd9-58baa6c99267"
version = "0.1.10"

[[deps.MPItrampoline_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "MPIPreferences", "TOML"]
git-tree-sha1 = "8eeb3c73bbc0ca203d0dc8dad4008350bbe5797b"
uuid = "f1f71cc9-e9ae-5b93-9b94-4fe0e1ad3748"
version = "5.3.1+1"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "2fa9ee3e63fd3a4f7a9a4f4744a52f4856de82df"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.13"

[[deps.Makie]]
deps = ["Animations", "Base64", "CRC32c", "ColorBrewer", "ColorSchemes", "ColorTypes", "Colors", "Contour", "DelaunayTriangulation", "Distributions", "DocStringExtensions", "Downloads", "FFMPEG_jll", "FileIO", "FilePaths", "FixedPointNumbers", "Formatting", "FreeType", "FreeTypeAbstraction", "GeometryBasics", "GridLayoutBase", "ImageIO", "InteractiveUtils", "IntervalArithmetic", "IntervalSets", "Isoband", "KernelDensity", "LaTeXStrings", "LinearAlgebra", "MacroTools", "MakieCore", "Markdown", "MathTeXEngine", "Observables", "OffsetArrays", "Packing", "PlotUtils", "PolygonOps", "PrecompileTools", "Printf", "REPL", "Random", "RelocatableFolders", "Scratch", "ShaderAbstractions", "Showoff", "SignedDistanceFields", "SparseArrays", "StableHashTraits", "Statistics", "StatsBase", "StatsFuns", "StructArrays", "TriplotBase", "UnicodeFun"]
git-tree-sha1 = "40c5dfbb99c91835171536cd571fe6f1ba18ff97"
uuid = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
version = "0.20.7"

[[deps.MakieCore]]
deps = ["Observables", "REPL"]
git-tree-sha1 = "248b7a4be0f92b497f7a331aed02c1e9a878f46b"
uuid = "20f20a25-4f0e-4fdf-b5d1-57303727442b"
version = "0.7.3"

[[deps.MappedArrays]]
git-tree-sha1 = "2dab0221fe2b0f2cb6754eaa743cc266339f527e"
uuid = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
version = "0.4.2"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "8b40681684df46785a0012d352982e22ac3be59e"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.25.2"

[[deps.MathTeXEngine]]
deps = ["AbstractTrees", "Automa", "DataStructures", "FreeTypeAbstraction", "GeometryBasics", "LaTeXStrings", "REPL", "RelocatableFolders", "UnicodeFun"]
git-tree-sha1 = "96ca8a313eb6437db5ffe946c457a401bbb8ce1d"
uuid = "0a4f8689-d25c-4efe-a92b-7142dfc1aa53"
version = "0.5.7"

[[deps.MatrixFactorizations]]
deps = ["ArrayLayouts", "LinearAlgebra", "Printf", "Random"]
git-tree-sha1 = "78f6e33434939b0ac9ba1df81e6d005ee85a7396"
uuid = "a3b82374-2e81-5b9e-98ce-41277c0e4c87"
version = "2.1.0"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+1"

[[deps.Memoize]]
deps = ["MacroTools"]
git-tree-sha1 = "2b1dfcba103de714d31c033b5dacc2e4a12c7caa"
uuid = "c03570c3-d221-55d1-a50c-7939bbd78826"
version = "0.4.4"

[[deps.Meshes]]
deps = ["Bessels", "CircularArrays", "Distances", "LinearAlgebra", "NearestNeighbors", "Random", "Rotations", "SparseArrays", "StaticArrays", "StatsBase", "Transducers", "TransformsBase", "Unitful"]
git-tree-sha1 = "5d7327ec086bbe18cd281cecae0e9fb7b79f357c"
uuid = "eacbb407-ea5a-433e-ab97-5258b1ca43fa"
version = "0.40.4"
weakdeps = ["Makie"]

    [deps.Meshes.extensions]
    MeshesMakieExt = "Makie"

[[deps.MicroCollections]]
deps = ["Accessors", "BangBang", "InitialValues"]
git-tree-sha1 = "44d32db644e84c75dab479f1bc15ee76a1a3618f"
uuid = "128add7d-3638-4c79-886c-908ea0c25c34"
version = "0.2.0"

[[deps.MicrosoftMPI_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b01beb91d20b0d1312a9471a36017b5b339d26de"
uuid = "9237b28f-5490-5468-be7b-bb81f5f5e6cf"
version = "10.1.4+1"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.Mods]]
git-tree-sha1 = "924f962b524a71eef7a21dae1e6853817f9b658f"
uuid = "7475f97c-0381-53b1-977b-4c60186c8d62"
version = "2.2.4"

[[deps.MosaicViews]]
deps = ["MappedArrays", "OffsetArrays", "PaddedViews", "StackViews"]
git-tree-sha1 = "7b86a5d4d70a9f5cdf2dacb3cbe6d251d1a61dbe"
uuid = "e94cdb99-869f-56ef-bcf0-1ae2bcbe0389"
version = "0.3.4"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.1.10"

[[deps.Multisets]]
git-tree-sha1 = "8d852646862c96e226367ad10c8af56099b4047e"
uuid = "3b2b4ff1-bcff-5658-a3ee-dbcf1ce5ac09"
version = "0.4.4"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "806eea990fb41f9b36f1253e5697aa645bf6a9f8"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.4.0"

[[deps.NCDatasets]]
deps = ["CFTime", "CommonDataModel", "DataStructures", "Dates", "DiskArrays", "NetCDF_jll", "NetworkOptions", "Printf"]
git-tree-sha1 = "79400cceb1655e7b2fe528a7b114c785bc152e59"
uuid = "85f8d34a-cbdd-5861-8df4-14fed0d494ab"
version = "0.14.1"

[[deps.NLSolversBase]]
deps = ["DiffResults", "Distributed", "FiniteDiff", "ForwardDiff"]
git-tree-sha1 = "a0b464d183da839699f4c79e7606d9d186ec172c"
uuid = "d41bc354-129a-5804-8e4c-c37616107c6c"
version = "7.8.3"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.NearestNeighbors]]
deps = ["Distances", "StaticArrays"]
git-tree-sha1 = "ded64ff6d4fdd1cb68dfcbb818c69e144a5b2e4c"
uuid = "b8a86587-4115-5ab1-83bc-aa920d37bbce"
version = "0.4.16"

[[deps.NelderMead]]
git-tree-sha1 = "25abc2f9b1c752e69229f37909461befa7c1f85d"
uuid = "2f6b4ddb-b4ff-44c0-b59b-2ab99302f970"
version = "0.4.0"

[[deps.NetCDF_jll]]
deps = ["Artifacts", "Blosc_jll", "Bzip2_jll", "HDF5_jll", "JLLWrappers", "LibCURL_jll", "Libdl", "OpenMPI_jll", "XML2_jll", "Zlib_jll", "Zstd_jll", "libzip_jll"]
git-tree-sha1 = "a8af1798e4eb9ff768ce7fdefc0e957097793f15"
uuid = "7243133f-43d8-5620-bbf4-c2c921802cf3"
version = "400.902.209+0"

[[deps.Netpbm]]
deps = ["FileIO", "ImageCore", "ImageMetadata"]
git-tree-sha1 = "d92b107dbb887293622df7697a2223f9f8176fcd"
uuid = "f09324ee-3d7c-5217-9330-fc30815ba969"
version = "1.1.1"

[[deps.Nettle_jll]]
deps = ["Artifacts", "GMP_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "eca63e3847dad608cfa6a3329b95ef674c7160b4"
uuid = "4c82536e-c426-54e4-b420-14f461c4ed8b"
version = "3.7.2+0"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.Observables]]
git-tree-sha1 = "7438a59546cf62428fc9d1bc94729146d37a7225"
uuid = "510215fc-4207-5dde-b226-833fc4488ee2"
version = "0.5.5"

[[deps.OffsetArrays]]
git-tree-sha1 = "6a731f2b5c03157418a20c12195eb4b74c8f8621"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.13.0"
weakdeps = ["Adapt"]

    [deps.OffsetArrays.extensions]
    OffsetArraysAdaptExt = "Adapt"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.23+4"

[[deps.OpenEXR]]
deps = ["Colors", "FileIO", "OpenEXR_jll"]
git-tree-sha1 = "327f53360fdb54df7ecd01e96ef1983536d1e633"
uuid = "52e1d378-f018-4a11-a4be-720524705ac7"
version = "0.3.2"

[[deps.OpenEXR_jll]]
deps = ["Artifacts", "Imath_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "a4ca623df1ae99d09bc9868b008262d0c0ac1e4f"
uuid = "18a262bb-aa17-5467-a713-aee519bc75cb"
version = "3.1.4+0"

[[deps.OpenJpeg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libtiff_jll", "LittleCMS_jll", "libpng_jll"]
git-tree-sha1 = "8d4c87ffaf09dbdd82bcf8c939843e94dd424df2"
uuid = "643b3616-a352-519d-856d-80112ee9badc"
version = "2.5.0+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+2"

[[deps.OpenMPI_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "MPIPreferences", "TOML"]
git-tree-sha1 = "e25c1778a98e34219a00455d6e4384e017ea9762"
uuid = "fe0851c0-eecd-5654-98d4-656369965a5c"
version = "4.1.6+0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "60e3045590bd104a16fefb12836c00c0ef8c7f8c"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.0.13+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Optim]]
deps = ["Compat", "FillArrays", "ForwardDiff", "LineSearches", "LinearAlgebra", "MathOptInterface", "NLSolversBase", "NaNMath", "Parameters", "PositiveFactorizations", "Printf", "SparseArrays", "StatsBase"]
git-tree-sha1 = "d024bfb56144d947d4fafcd9cb5cafbe3410b133"
uuid = "429524aa-4258-5aef-a3af-852621145aeb"
version = "1.9.2"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "dfdf5519f235516220579f949664f1bf44e741c5"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.3"

[[deps.P11Kit_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "2cd396108e178f3ae8dedbd8e938a18726ab2fbf"
uuid = "c2071276-7c44-58a7-b746-946036e04d0a"
version = "0.24.1+0"

[[deps.PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"
version = "10.42.0+1"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "949347156c25054de2db3b166c52ac4728cbad65"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.31"

[[deps.PNGFiles]]
deps = ["Base64", "CEnum", "ImageCore", "IndirectArrays", "OffsetArrays", "libpng_jll"]
git-tree-sha1 = "67186a2bc9a90f9f85ff3cc8277868961fb57cbd"
uuid = "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
version = "0.4.3"

[[deps.PROJ_jll]]
deps = ["Artifacts", "JLLWrappers", "LibCURL_jll", "Libdl", "Libtiff_jll", "SQLite_jll"]
git-tree-sha1 = "f3e45027ea0f44a2725fbedfdb7ed118d5deec8d"
uuid = "58948b4f-47e0-5654-a9ad-f609743f8632"
version = "901.300.0+0"

[[deps.PackageExtensionCompat]]
git-tree-sha1 = "fb28e33b8a95c4cee25ce296c817d89cc2e53518"
uuid = "65ce6f38-6b18-4e1d-a461-8949797d7930"
version = "1.0.2"
weakdeps = ["Requires", "TOML"]

[[deps.Packing]]
deps = ["GeometryBasics"]
git-tree-sha1 = "ec3edfe723df33528e085e632414499f26650501"
uuid = "19eb6ba3-879d-56ad-ad62-d5c202156566"
version = "0.5.0"

[[deps.PaddedViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "0fac6313486baae819364c52b4f483450a9d793f"
uuid = "5432bcbf-9aad-5242-b902-cca2824c8663"
version = "0.5.12"

[[deps.Pango_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "FriBidi_jll", "Glib_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "4745216e94f71cb768d58330b059c9b76f32cb66"
uuid = "36c8627f-9965-5494-a995-c6b170f724f3"
version = "1.50.14+0"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parquet2]]
deps = ["AbstractTrees", "BitIntegers", "CodecLz4", "CodecZlib", "CodecZstd", "DataAPI", "Dates", "DecFP", "FilePathsBase", "FillArrays", "JSON3", "LazyArrays", "LightBSON", "Mmap", "OrderedCollections", "PooledArrays", "PrecompileTools", "SentinelArrays", "Snappy", "StaticArrays", "TableOperations", "Tables", "Thrift2", "Transducers", "UUIDs", "WeakRefStrings"]
git-tree-sha1 = "3d447fe6823aa2c1697902f750ffd1a0ef51f6f2"
uuid = "98572fba-bba0-415d-956f-fa77e587d26d"
version = "0.2.20"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[deps.Permutations]]
deps = ["Combinatorics", "LinearAlgebra", "Random"]
git-tree-sha1 = "eb3f9df2457819bf0a9019bd93cc451697a0751e"
uuid = "2ae35dd2-176d-5d53-8349-f30d82d94d4f"
version = "0.4.20"

[[deps.PikaParser]]
deps = ["DocStringExtensions"]
git-tree-sha1 = "d6ff87de27ff3082131f31a714d25ab6d0a88abf"
uuid = "3bbf5609-3e7b-44cd-8549-7c69f321e792"
version = "0.6.1"

[[deps.Pixman_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LLVMOpenMP_jll", "Libdl"]
git-tree-sha1 = "64779bc4c9784fee475689a1752ef4d5747c5e87"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.42.2+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.10.0"

[[deps.PkgVersion]]
deps = ["Pkg"]
git-tree-sha1 = "f9501cc0430a26bc3d156ae1b5b0c1b47af4d6da"
uuid = "eebad327-c553-4316-9ea0-9fa01ccd7688"
version = "0.3.3"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "PrecompileTools", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "862942baf5663da528f66d24996eb6da85218e76"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.4.0"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "68723afdb616445c6caaef6255067a8339f91325"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.55"

[[deps.PlyIO]]
git-tree-sha1 = "74619231a7aa262a76f82ae05c7385622d8a5945"
uuid = "42171d58-473b-503a-8d5f-782019eb09ec"
version = "1.1.2"

[[deps.PolygonOps]]
git-tree-sha1 = "77b3d3605fc1cd0b42d95eba87dfcd2bf67d5ff6"
uuid = "647866c9-e3ac-4575-94e7-e3d426903924"
version = "0.1.2"

[[deps.Polynomials]]
deps = ["LinearAlgebra", "RecipesBase", "Setfield", "SparseArrays"]
git-tree-sha1 = "a9c7a523d5ed375be3983db190f6a5874ae9286d"
uuid = "f27b6e38-b328-58d1-80ce-0feddd5e7a45"
version = "4.0.6"
weakdeps = ["ChainRulesCore", "FFTW", "MakieCore", "MutableArithmetics"]

    [deps.Polynomials.extensions]
    PolynomialsChainRulesCoreExt = "ChainRulesCore"
    PolynomialsFFTWExt = "FFTW"
    PolynomialsMakieCoreExt = "MakieCore"
    PolynomialsMutableArithmeticsExt = "MutableArithmetics"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "36d8b4b899628fb92c2749eb488d884a926614d3"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.3"

[[deps.PositiveFactorizations]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "17275485f373e6673f7e7f97051f703ed5b15b20"
uuid = "85a6dd25-e78a-55b7-8502-1745935b8125"
version = "0.2.4"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "03b4c25b43cb84cee5c90aa9b5ea0a78fd848d2f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.0"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "00805cd429dcb4870060ff49ef443486c262e38e"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.1"

[[deps.PrettyTables]]
deps = ["Crayons", "LaTeXStrings", "Markdown", "PrecompileTools", "Printf", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "88b895d13d53b5577fd53379d913b9ab9ac82660"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.3.1"

[[deps.Primes]]
deps = ["IntegerMathUtils"]
git-tree-sha1 = "1d05623b5952aed1307bf8b43bec8b8d1ef94b6e"
uuid = "27ebfcd6-29c5-5fa9-bf4b-fb8fc14df3ae"
version = "0.5.5"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.ProgressLogging]]
deps = ["Logging", "SHA", "UUIDs"]
git-tree-sha1 = "80d919dee55b9c50e8d9e2da5eeafff3fe58b539"
uuid = "33c8b6b6-d38a-422a-b730-caa89a2f386c"
version = "0.1.4"

[[deps.ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "00099623ffee15972c16111bcf84c58a0051257c"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.9.0"

[[deps.Proj]]
deps = ["CEnum", "CoordinateTransformations", "GeoFormatTypes", "GeoInterface", "NetworkOptions", "PROJ_jll"]
git-tree-sha1 = "76ab3cbf876f3c859b6cc5817d8262809add3e13"
uuid = "c94c279d-25a6-4763-9509-64d165bea63e"
version = "1.7.0"

[[deps.QOI]]
deps = ["ColorTypes", "FileIO", "FixedPointNumbers"]
git-tree-sha1 = "18e8f4d1426e965c7b532ddd260599e1510d26ce"
uuid = "4b34888f-f399-49d4-9bb3-47ed5cae4e65"
version = "1.0.0"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "9b23c31e76e333e6fb4c1595ae6afa74966a729e"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.9.4"

[[deps.Quaternions]]
deps = ["LinearAlgebra", "Random", "RealDot"]
git-tree-sha1 = "994cc27cdacca10e68feb291673ec3a76aa2fae9"
uuid = "94ee1d12-ae83-5a48-8b1c-48b8ff168ae0"
version = "0.7.6"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.RangeArrays]]
git-tree-sha1 = "b9039e93773ddcfc828f12aadf7115b4b4d225f5"
uuid = "b3c3ace0-ae52-54e7-9d0b-2c1406fd6b9d"
version = "0.3.2"

[[deps.Ratios]]
deps = ["Requires"]
git-tree-sha1 = "1342a47bf3260ee108163042310d26f2be5ec90b"
uuid = "c84ed2f1-dad5-54f0-aa8e-dbefe2724439"
version = "0.4.5"
weakdeps = ["FixedPointNumbers"]

    [deps.Ratios.extensions]
    RatiosFixedPointNumbersExt = "FixedPointNumbers"

[[deps.ReadVTK]]
deps = ["Base64", "CodecZlib", "Downloads", "LightXML", "Reexport", "VTKBase"]
git-tree-sha1 = "f8a48e99ca616b46ad62356257dd21b9bb522024"
uuid = "dc215faf-f008-4882-a9f7-a79a826fadc3"
version = "0.2.0"

[[deps.RealDot]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "9f0a1b71baaf7650f4fa8a1d168c7fb6ee41f0c9"
uuid = "c1ae055f-0cd5-4b69-90a6-9a35b1a98df9"
version = "0.1.0"

[[deps.RecipesBase]]
deps = ["PrecompileTools"]
git-tree-sha1 = "5c3d09cc4f31f5fc6af001c250bf1278733100ff"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.4"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "ffdaf70d81cf6ff22c2b6e733c900c3321cab864"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.1"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.RingLists]]
deps = ["Random"]
git-tree-sha1 = "f39da63aa6d2d88e0c1bd20ed6a3ff9ea7171ada"
uuid = "286e9d63-9694-5540-9e3c-4e6708fa07b2"
version = "0.2.8"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "f65dcb5fa46aee0cf9ed6274ccbd597adc49aa7b"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.1"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6ed52fdd3382cf21947b15e8870ac0ddbff736da"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.4.0+0"

[[deps.Rotations]]
deps = ["LinearAlgebra", "Quaternions", "Random", "StaticArrays"]
git-tree-sha1 = "2a0a5d8569f481ff8840e3b7c84bbf188db6a3fe"
uuid = "6038ab10-8711-5258-84ad-4b1120ba62dc"
version = "1.7.0"
weakdeps = ["RecipesBase"]

    [deps.Rotations.extensions]
    RotationsRecipesBaseExt = "RecipesBase"

[[deps.RoundingEmulator]]
git-tree-sha1 = "40b9edad2e5287e05bd413a38f61a8ff55b9557b"
uuid = "5eaf0fd0-dfba-4ccb-bf02-d820a40db705"
version = "0.2.1"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SQLite_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "75e28667a36b5650b5cc4baa266c5760c3672275"
uuid = "76ed43ae-9a5d-5a62-8c75-30186b810ce8"
version = "3.45.0+0"

[[deps.ScikitLearnBase]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "7877e55c1523a4b336b433da39c8e8c08d2f221f"
uuid = "6e75b9c4-186b-50bd-896f-2d2496a4843e"
version = "0.5.0"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "3bac05bc7e74a75fd9cba4295cde4045d9fe2386"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.1"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "0e7508ff27ba32f26cd459474ca2ede1bc10991f"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.1"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[deps.ShaderAbstractions]]
deps = ["ColorTypes", "FixedPointNumbers", "GeometryBasics", "LinearAlgebra", "Observables", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "79123bc60c5507f035e6d1d9e563bb2971954ec8"
uuid = "65257c39-d410-5151-9873-9b3e5be5013e"
version = "0.4.1"

[[deps.Shapefile]]
deps = ["DBFTables", "Extents", "GeoFormatTypes", "GeoInterface", "GeoInterfaceMakie", "GeoInterfaceRecipes", "OrderedCollections", "RecipesBase", "Tables"]
git-tree-sha1 = "efc2b1829c272bffbde1282ff2a076cdfa31fae6"
uuid = "8e980c4a-a4fe-5da2-b3a7-4b4b0353a2f4"
version = "0.12.0"
weakdeps = ["Makie"]

    [deps.Shapefile.extensions]
    ShapefileMakieExt = "Makie"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.ShiftedArrays]]
git-tree-sha1 = "503688b59397b3307443af35cd953a13e8005c16"
uuid = "1277b4bf-5013-50f5-be3d-901d8477a67a"
version = "2.0.0"

[[deps.ShortCodes]]
deps = ["Base64", "CodecZlib", "Downloads", "JSON3", "Memoize", "URIs", "UUIDs"]
git-tree-sha1 = "5844ee60d9fd30a891d48bab77ac9e16791a0a57"
uuid = "f62ebe17-55c5-4640-972f-b59c0dd11ccf"
version = "0.3.6"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.SignedDistanceFields]]
deps = ["Random", "Statistics", "Test"]
git-tree-sha1 = "d263a08ec505853a5ff1c1ebde2070419e3f28e9"
uuid = "73760f76-fbc4-59ce-8f25-708e95d2df96"
version = "0.4.0"

[[deps.SimpleGraphs]]
deps = ["AbstractLattices", "Combinatorics", "DataStructures", "IterTools", "LightXML", "LinearAlgebra", "LinearAlgebraX", "Optim", "Primes", "Random", "RingLists", "SimplePartitions", "SimplePolynomials", "SimpleRandom", "SparseArrays", "Statistics"]
git-tree-sha1 = "f65caa24a622f985cc341de81d3f9744435d0d0f"
uuid = "55797a34-41de-5266-9ec1-32ac4eb504d3"
version = "0.8.6"

[[deps.SimplePartitions]]
deps = ["AbstractLattices", "DataStructures", "Permutations"]
git-tree-sha1 = "e9330391d04241eafdc358713b48396619c83bcb"
uuid = "ec83eff0-a5b5-5643-ae32-5cbf6eedec9d"
version = "0.3.1"

[[deps.SimplePolynomials]]
deps = ["Mods", "Multisets", "Polynomials", "Primes"]
git-tree-sha1 = "7063828369cafa93f3187b3d0159f05582011405"
uuid = "cc47b68c-3164-5771-a705-2bc0097375a0"
version = "0.2.17"

[[deps.SimpleRandom]]
deps = ["Distributions", "LinearAlgebra", "Random"]
git-tree-sha1 = "3a6fb395e37afab81aeea85bae48a4db5cd7244a"
uuid = "a6525b86-64cd-54fa-8f65-62fc48bdc0e8"
version = "0.3.1"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.Sixel]]
deps = ["Dates", "FileIO", "ImageCore", "IndirectArrays", "OffsetArrays", "REPL", "libsixel_jll"]
git-tree-sha1 = "2da10356e31327c7096832eb9cd86307a50b1eb6"
uuid = "45858cf5-a6b0-47a3-bbea-62219f50df47"
version = "0.1.3"

[[deps.Snappy]]
deps = ["CEnum", "snappy_jll"]
git-tree-sha1 = "72bae53c0691f4b6fd259587dab8821ae0e025f6"
uuid = "59d4ed8c-697a-5b28-a4c7-fe95c22820f9"
version = "0.4.2"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "66e0a8e672a0bdfca2c3f5937efb8538b9ddc085"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.1"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.10.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "e2cfc4012a19088254b3950b85c3c1d8882d864d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.3.1"
weakdeps = ["ChainRulesCore"]

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

[[deps.SplitApplyCombine]]
deps = ["Dictionaries", "Indexing"]
git-tree-sha1 = "c06d695d51cfb2187e6848e98d6252df9101c588"
uuid = "03a91e81-4c3e-53e1-a0a4-9c0c8f19dd66"
version = "1.2.3"

[[deps.SplittablesBase]]
deps = ["Setfield", "Test"]
git-tree-sha1 = "e08a62abc517eb79667d0a29dc08a3b589516bb5"
uuid = "171d559e-b47b-412a-8079-5efa626c420e"
version = "0.1.15"

[[deps.StableHashTraits]]
deps = ["Compat", "PikaParser", "SHA", "Tables", "TupleTools"]
git-tree-sha1 = "662f56ffe22b3985f3be7474f0aecbaf214ecf0f"
uuid = "c5dd0088-6c3f-4803-b00e-f31a60c170fa"
version = "1.1.6"

[[deps.StackViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "46e589465204cd0c08b4bd97385e4fa79a0c770c"
uuid = "cae243ae-269e-4f55-b966-ac2d0dc13c15"
version = "0.1.1"

[[deps.Static]]
deps = ["IfElse"]
git-tree-sha1 = "d2fdac9ff3906e27f7a618d47b676941baa6c80c"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.8.10"

[[deps.StaticArrayInterface]]
deps = ["ArrayInterface", "Compat", "IfElse", "LinearAlgebra", "PrecompileTools", "Requires", "SparseArrays", "Static", "SuiteSparse"]
git-tree-sha1 = "5d66818a39bb04bf328e92bc933ec5b4ee88e436"
uuid = "0d7ed370-da01-4f52-bd93-41d350b8b718"
version = "1.5.0"
weakdeps = ["OffsetArrays", "StaticArrays"]

    [deps.StaticArrayInterface.extensions]
    StaticArrayInterfaceOffsetArraysExt = "OffsetArrays"
    StaticArrayInterfaceStaticArraysExt = "StaticArrays"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "7b0e9c14c624e435076d19aea1e5cbdec2b9ca37"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.2"
weakdeps = ["ChainRulesCore", "Statistics"]

    [deps.StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

[[deps.StaticArraysCore]]
git-tree-sha1 = "36b3d696ce6366023a0ea192b4cd442268995a0d"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.2"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.10.0"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1ff449ad350c9c4cbc756624d6f8a8c3ef56d3ed"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.7.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "1d77abd07f617c4868c33d4f5b9e1dbb2643c9cf"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.34.2"

[[deps.StatsFuns]]
deps = ["HypergeometricFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "f625d686d5a88bcd2b15cd81f18f98186fdc0c9a"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "1.3.0"
weakdeps = ["ChainRulesCore", "InverseFunctions"]

    [deps.StatsFuns.extensions]
    StatsFunsChainRulesCoreExt = "ChainRulesCore"
    StatsFunsInverseFunctionsExt = "InverseFunctions"

[[deps.StatsLearnModels]]
deps = ["ColumnSelectors", "DataScienceTraits", "DecisionTree", "Distances", "Distributions", "GLM", "NearestNeighbors", "StatsBase", "TableTransforms", "Tables"]
git-tree-sha1 = "289ae52082d5a4962f0cb85f208d1eec13020572"
uuid = "c146b59d-1589-421c-8e09-a22e554fd05c"
version = "0.3.0"

    [deps.StatsLearnModels.extensions]
    StatsLearnModelsMLJModelInterfaceExt = "MLJModelInterface"

    [deps.StatsLearnModels.weakdeps]
    MLJModelInterface = "e80e1ace-859a-464e-9ed9-23947d8ae3ea"

[[deps.StatsModels]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "Printf", "REPL", "ShiftedArrays", "SparseArrays", "StatsAPI", "StatsBase", "StatsFuns", "Tables"]
git-tree-sha1 = "5cf6c4583533ee38639f73b880f35fc85f2941e0"
uuid = "3eaba693-59b7-5ba5-a881-562e759f1c8d"
version = "0.7.3"

[[deps.StringManipulation]]
deps = ["PrecompileTools"]
git-tree-sha1 = "a04cabe79c5f01f4d723cc6704070ada0b9d46d5"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.4"

[[deps.StructArrays]]
deps = ["Adapt", "ConstructionBase", "DataAPI", "GPUArraysCore", "StaticArraysCore", "Tables"]
git-tree-sha1 = "1b0b1205a56dc288b71b1961d48e351520702e24"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.17"

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "ca4bccb03acf9faaf4137a9abc1881ed1841aa70"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.10.0"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.2.1+1"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableDistances]]
deps = ["CategoricalArrays", "CoDa", "DataScienceTraits", "Distances", "Statistics", "Tables"]
git-tree-sha1 = "6913b6327c6fe161bd087ef1399a61fb5671f5e2"
uuid = "e5d66e97-8c70-46bb-8b66-04a2d73ad782"
version = "0.4.2"

[[deps.TableOperations]]
deps = ["SentinelArrays", "Tables", "Test"]
git-tree-sha1 = "e383c87cf2a1dc41fa30c093b2a19877c83e1bc1"
uuid = "ab02a1b2-a7df-11e8-156e-fb1833f50b87"
version = "1.2.0"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.TableTransforms]]
deps = ["AbstractTrees", "CategoricalArrays", "CoDa", "ColumnSelectors", "DataScienceTraits", "Distributions", "InverseFunctions", "LinearAlgebra", "NelderMead", "PrettyTables", "Random", "Statistics", "StatsBase", "Tables", "Transducers", "TransformsBase", "Unitful"]
git-tree-sha1 = "3efc3a999c212a7661ba04cf4fbd649c8eebe224"
uuid = "0d432bfd-3ee1-4ac1-886a-39f05cc69a3e"
version = "1.29.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "cb76cf677714c095e535e3501ac7954732aeea2d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.11.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.Thrift2]]
deps = ["MacroTools", "OrderedCollections", "PrecompileTools"]
git-tree-sha1 = "00d618714271f283ea3829ab058d5e5bd1847f85"
uuid = "9be31aac-5446-47db-bfeb-416acd2e4415"
version = "0.1.4"

[[deps.Thrift_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "boost_jll"]
git-tree-sha1 = "fd7da49fae680c18aa59f421f0ba468e658a2d7a"
uuid = "e0b8ae26-5307-5830-91fd-398402328850"
version = "0.16.0+0"

[[deps.TiffImages]]
deps = ["ColorTypes", "DataStructures", "DocStringExtensions", "FileIO", "FixedPointNumbers", "IndirectArrays", "Inflate", "Mmap", "OffsetArrays", "PkgVersion", "ProgressMeter", "UUIDs"]
git-tree-sha1 = "34cc045dd0aaa59b8bbe86c644679bc57f1d5bd0"
uuid = "731e570b-9d59-4bfa-96dc-6df516fadf69"
version = "0.6.8"

[[deps.TranscodingStreams]]
git-tree-sha1 = "54194d92959d8ebaa8e26227dbe3cdefcdcd594f"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.10.3"
weakdeps = ["Random", "Test"]

    [deps.TranscodingStreams.extensions]
    TestExt = ["Test", "Random"]

[[deps.Transducers]]
deps = ["Accessors", "Adapt", "ArgCheck", "BangBang", "Baselet", "CompositionsBase", "ConstructionBase", "DefineSingletons", "Distributed", "InitialValues", "Logging", "Markdown", "MicroCollections", "Requires", "SplittablesBase", "Tables"]
git-tree-sha1 = "47e516e2eabd0cf1304cd67839d9a85d52dd659d"
uuid = "28d57a85-8fef-5791-bfe6-a80928e7c999"
version = "0.4.81"

    [deps.Transducers.extensions]
    TransducersBlockArraysExt = "BlockArrays"
    TransducersDataFramesExt = "DataFrames"
    TransducersLazyArraysExt = "LazyArrays"
    TransducersOnlineStatsBaseExt = "OnlineStatsBase"
    TransducersReferenceablesExt = "Referenceables"

    [deps.Transducers.weakdeps]
    BlockArrays = "8e7c35d0-a365-5155-bbbb-fb81a777f24e"
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    LazyArrays = "5078a376-72f3-5289-bfd5-ec5146d43c02"
    OnlineStatsBase = "925886fa-5bf2-5e8e-b522-a9147a512338"
    Referenceables = "42d2dcc6-99eb-4e98-b66c-637b7d73030e"

[[deps.TransformsBase]]
deps = ["AbstractTrees"]
git-tree-sha1 = "484610e9b25a45f015f3e695c6d307e91883f2d3"
uuid = "28dd2a49-a57a-4bfb-84ca-1a49db9b96b8"
version = "1.4.1"

[[deps.Tricks]]
git-tree-sha1 = "eae1bb484cd63b36999ee58be2de6c178105112f"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.8"

[[deps.TriplotBase]]
git-tree-sha1 = "4d4ed7f294cda19382ff7de4c137d24d16adc89b"
uuid = "981d1d27-644d-49a2-9326-4793e63143c3"
version = "0.1.0"

[[deps.TupleTools]]
git-tree-sha1 = "155515ed4c4236db30049ac1495e2969cc06be9d"
uuid = "9d95972d-f1c8-5527-a6e0-b4b365fa01f6"
version = "1.4.3"

[[deps.TypedTables]]
deps = ["Adapt", "Dictionaries", "Indexing", "SplitApplyCombine", "Tables", "Unicode"]
git-tree-sha1 = "84fd7dadde577e01eb4323b7e7b9cb51c62c60d4"
uuid = "9d95f2ec-7b3d-5a63-8d20-e2491e220bb9"
version = "1.4.6"

[[deps.URIs]]
git-tree-sha1 = "67db6cc7b3821e19ebe75791a9dd19c9b1188f2b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.5.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.Unitful]]
deps = ["Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "3c793be6df9dd77a0cf49d80984ef9ff996948fa"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.19.0"
weakdeps = ["ConstructionBase", "InverseFunctions"]

    [deps.Unitful.extensions]
    ConstructionBaseUnitfulExt = "ConstructionBase"
    InverseFunctionsUnitfulExt = "InverseFunctions"

[[deps.UnsafeArrays]]
git-tree-sha1 = "e7f1c67ba99ac6df440de191fa4d5cbfcbdddcd1"
uuid = "c4a57d5a-5b31-53a6-b365-19f8c011fbd6"
version = "1.0.5"

[[deps.VTKBase]]
git-tree-sha1 = "c2d0db3ef09f1942d08ea455a9e252594be5f3b6"
uuid = "4004b06d-e244-455f-a6ce-a5f9919cc534"
version = "1.0.1"

[[deps.WeakRefStrings]]
deps = ["DataAPI", "InlineStrings", "Parsers"]
git-tree-sha1 = "b1be2855ed9ed8eac54e5caff2afcdb442d52c23"
uuid = "ea10d353-3f73-51f8-a26c-33c1cb351aa5"
version = "1.4.2"

[[deps.WellKnownGeometry]]
deps = ["GeoFormatTypes", "GeoInterface"]
git-tree-sha1 = "42d095d8a726aaa268a5b8acb4922a570dead137"
uuid = "0f680547-7be7-4555-8820-bb198eeb646b"
version = "0.2.2"

[[deps.WoodburyMatrices]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "c1a7aa6219628fcd757dede0ca95e245c5cd9511"
uuid = "efce3f68-66dc-5838-9240-27a6d6f5f9b6"
version = "1.0.0"

[[deps.WorkerUtilities]]
git-tree-sha1 = "cd1659ba0d57b71a464a29e64dbc67cfe83d54e7"
uuid = "76eceee3-57b5-4d4a-8e66-0e911cebbf60"
version = "1.6.1"

[[deps.WriteVTK]]
deps = ["Base64", "CodecZlib", "FillArrays", "LightXML", "TranscodingStreams", "VTKBase"]
git-tree-sha1 = "5817a62d8a1d00ce36bb418aceafaa49cff81b65"
uuid = "64499a7a-5c06-52f2-abe2-ccb03c286192"
version = "1.18.2"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Zlib_jll"]
git-tree-sha1 = "801cbe47eae69adc50f36c3caec4758d2650741b"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.12.2+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.XZ_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "522b8414d40c4cbbab8dee346ac3a09f9768f25d"
uuid = "ffd25f8a-64ca-5728-b0f7-c24cf3aae800"
version = "5.4.5+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "afead5aba5aa507ad5a3bf01f58f82c8d1403495"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.8.6+0"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6035850dcc70518ca32f012e46015b9beeda49d8"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.11+0"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "34d526d318358a859d7de23da945578e8e8727b7"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.4+0"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "8fdda4c692503d44d04a0603d9ac0982054635f9"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.1+0"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "b4bfde5d5b652e22b9c790ad00af08b6d042b97d"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.15.0+0"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e92a1a012a10506618f10b7047e478403a046c77"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.5.0+0"

[[deps.ZipFile]]
deps = ["Libdl", "Printf", "Zlib_jll"]
git-tree-sha1 = "f492b7fe1698e623024e873244f10d89c95c340a"
uuid = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
version = "0.10.1"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "49ce682769cd5de6c72dcf1b94ed7790cd08974c"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.5+0"

[[deps.boost_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "7a89efe0137720ca82f99e8daa526d23120d0d37"
uuid = "28df3c45-c428-5900-9ff8-a3135698ca75"
version = "1.76.0+1"

[[deps.eccodes_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenJpeg_jll", "libaec_jll", "libpng_jll"]
git-tree-sha1 = "8576a3e2cb1d72fc78158e60e73b2f9b9667c0bd"
uuid = "b04048ba-5ccd-5610-b3f6-85129a548705"
version = "2.28.0+0"

[[deps.isoband_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51b5eeb3f98367157a7a12a1fb0aa5328946c03c"
uuid = "9a68df92-36a6-505f-a73e-abb412b6bfb4"
version = "0.2.3+0"

[[deps.libaec_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "eddd19a8dea6b139ea97bdc8a0e2667d4b661720"
uuid = "477f73a3-ac25-53e9-8cc3-50b2fa2566f0"
version = "1.0.6+1"

[[deps.libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+1"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libgeotiff_jll]]
deps = ["Artifacts", "JLLWrappers", "LibCURL_jll", "Libdl", "Libtiff_jll", "PROJ_jll"]
git-tree-sha1 = "b1df2e0dd651ef0d2e9f4bdf9f2c4b121f79b345"
uuid = "06c338fa-64ff-565b-ac2f-249532af990e"
version = "100.701.100+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "93284c28274d9e75218a416c65ec49d0e0fcdf3d"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.40+0"

[[deps.libsixel_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Pkg", "libpng_jll"]
git-tree-sha1 = "d4f63314c8aa1e48cd22aa0c17ed76cd1ae48c3c"
uuid = "075b6546-f08a-558a-be8f-8157d0f608a5"
version = "1.10.3+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[deps.libzip_jll]]
deps = ["Artifacts", "Bzip2_jll", "GnuTLS_jll", "JLLWrappers", "Libdl", "XZ_jll", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "9a6ac803f3c17fe7cf66430a8bfc7186800f08a4"
uuid = "337d8026-41b4-5cde-a456-74a10e5b31d1"
version = "1.9.2+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.52.0+1"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"

[[deps.snappy_jll]]
deps = ["Artifacts", "JLLWrappers", "LZO_jll", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "985c1da710b0e43f7c52f037441021dfd0e3be14"
uuid = "fe1e1685-f7be-5f59-ac9f-4ca204017dfd"
version = "1.1.9+1"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"
"""

# ╔═╡ Cell order:
# ╟─35f22f38-c795-11ee-3ae2-f3a931be8cf3
# ╠═f5a696d2-d0c0-495a-b62f-13ca08ad6f6d
# ╟─1b92f63e-04c1-41d5-84cb-69750b97cfc8
# ╠═e72f87b2-a52a-4a31-9627-34e6daa73a78
# ╠═3643ae60-c693-40b9-90c5-2d45c8c557b6
# ╠═e43048a7-f949-4ebc-8cfb-dc62d0b0d292
# ╟─5f79fd4c-7ae0-4324-8736-454d27af3ab8
# ╠═e8645ac9-b8bf-44ac-8493-469c2d8c96da
# ╠═7cc5801f-4d7f-4c91-8bc9-eb2b6c6dbeac
# ╟─2ef7d268-9b9f-4d70-a927-1086d98404b7
# ╠═0783e0c6-e603-405a-9d18-1620ab3ea091
# ╟─6e404cc0-05f6-45a7-949c-d2bd05c07fe1
# ╠═88579f53-3fcf-4f76-b57d-ca37a73a9711
# ╟─8bc8a608-ef52-4f40-946a-ef7a63503451
# ╠═55ad2d43-eaa2-4bcf-8c89-b97a449e2e4e
# ╠═d3fc5f23-9d7d-4973-afa5-6bc3478849eb
# ╟─16be52b4-7819-4aae-bebc-9cd1df63a8ce
# ╠═5e8fc45d-b13f-4c0f-8df4-26767e6c02cd
# ╠═4ac7e2aa-f9bd-48ea-9052-79ea58724336
# ╠═71583d73-21aa-4a09-aaca-7604707e48a7
# ╟─d00f473c-1cde-49a8-97e7-cd094b52a457
# ╠═a61534f2-aba5-4f43-9dc6-a87627c34f0d
# ╠═1e1787c1-6bae-45e5-b5ab-67b4e181c991
# ╟─ca2c4915-a392-4bde-bf5f-b9a4d1a240cf
# ╠═6b9a2eed-a306-4e6c-98d4-9294e708c679
# ╠═8f0936ca-7595-4761-aa76-c61691fd2083
# ╠═fcd663a3-6c82-478d-a3e2-0238835c1c8e
# ╟─e436f48b-4da7-47f9-a98b-bdc0324a3fb9
# ╠═62132f5b-1c25-4a8f-b662-d660da1aede2
# ╟─4db2d6aa-3224-4736-bd95-09d0d5aeba03
# ╠═721c5720-fa31-4ded-9581-547fa2b37b3b
# ╟─4f71c1d1-8719-49f1-8325-c942b7fcf56f
# ╠═bd04e9a8-a5be-4880-92b5-b3db5d55c727
# ╠═3a0c815b-b97a-4a45-b843-1ca10a4e6f25
# ╟─30eb77d2-adc6-43e3-b015-dce8df01f6a9
# ╟─a222d660-f8c1-432a-babd-2dc479234c10
# ╠═8d1de0e1-c587-4edb-98b7-8b6df440fe1d
# ╠═c7990171-41dc-43aa-84fd-6767b8c9ecdb
# ╠═6177a6bf-091d-403d-a414-596838af298c
# ╠═75d06b80-d99a-452f-9de7-eb816412a00e
# ╠═179c1a07-f0b3-4b83-b3d2-5746bbd7bd4e
# ╠═29615fc6-242c-4bb0-8353-cef2f3b714c9
# ╠═3652325a-faf2-48fb-8c98-5cbfd32848b1
# ╠═e4f8347b-b022-4328-ba40-a8138bdc2ad0
# ╟─cbbf20ca-fb2c-480e-a56b-527a4fa3daeb
# ╟─2bc94ef3-70bd-4b0e-b2d8-962fd79b7650
# ╠═95078d1c-c4ec-4d6b-99ac-20a0c96bf242
# ╟─00bbe80e-5c40-4d37-9c9d-1d871f61c72c
# ╟─94688148-4207-4843-bd55-1a81f98061cf
# ╠═ce0751b6-9595-4cfc-9187-68449dfb2c63
# ╟─ca15fc94-be19-4a9c-82fc-8fa98e61f06d
# ╠═3a8adc6d-8fcc-4f17-81be-e45e058b1412
# ╠═8fc7a3de-c59f-46ad-a3de-37ba45e2e137
# ╟─445fae4b-b84a-4de2-9ebd-aeac22340c2d
# ╠═3c1138db-5cb3-4bc4-bec6-0a06ee720343
# ╟─44027f7b-530b-4498-b60e-4140514a5d53
# ╠═1873c5b7-9a20-431b-8324-63585796f040
# ╠═54edbf03-59c2-4759-8e5b-8ee616fef264
# ╠═1bc014b5-f00d-4e24-b27a-104219527410
# ╠═7c87c2fa-1ffe-49eb-802b-160e004c10cd
# ╟─711971fb-0315-4095-b3c8-13d402d2fdec
# ╠═b860236e-91c3-41ae-81a0-be4c39130b65
# ╠═d05308bb-f2d3-430f-ac3b-7bd2c121ef22
# ╠═751dab8a-f6a7-44fc-8fc0-a55ffd033f11
# ╠═e65bacaa-da89-453c-bea0-e30606dde0d6
# ╠═a7202a46-f7f4-4b7e-94a0-73354a6b28f1
# ╟─fc63d341-4692-480f-bab7-5228e53ba8b5
# ╟─a9acb09e-8cc0-463a-afaa-637799dd70d3
# ╠═1afaeaca-e8d8-4e30-a9de-5a109f6384a7
# ╟─e1bb92d0-24f5-4b08-a095-2e9a11ba3807
# ╠═c1b1dfe5-6da7-4256-bfa0-715a6ebe68e7
# ╠═b11e27d2-a294-4e9f-bcbd-eb29fe598f06
# ╟─3c344dce-4648-41f4-b341-eba7705be7b7
# ╠═31669dab-b7a2-45e0-a373-89239b4ddad1
# ╠═a5c603f8-9e16-4f77-bea2-f5c05939c3eb
# ╠═94513167-c3c4-45f5-8ff7-8ba77277a61f
# ╠═4c7356d8-b5a9-40f8-a13c-405fc256d9f4
# ╟─e353e3c3-b9e0-4998-82ed-73ab000433b6
# ╠═1edf49d4-e61b-43ab-b9f8-e7f2b49773aa
# ╠═f323c5e7-8bad-4854-91e2-154ec0d1cb95
# ╟─c275ddec-d58c-4f29-886a-f79681d73523
# ╠═23c7306c-3f59-4a78-8dac-0dceebf451d5
# ╟─5603031d-61e3-4c25-b38f-a3cc480106b6
# ╠═ad7a0a32-36f3-42e1-9ff6-18d761d6b348
# ╠═172ea51b-2831-412e-a044-994af0bafb16
# ╟─bb835ca1-bc55-4322-8449-0351dd9137c0
# ╟─ca66910d-1c61-47ab-bbaa-da80dcefb462
# ╠═3bb77367-0947-4d0b-89e9-e1c75a73388d
# ╠═603564a1-b813-47a9-931a-98055a21b373
# ╟─710f0258-5eb9-44d5-9b47-7a816615a23a
# ╟─355a63ec-3179-4f95-b704-7ecedca419f2
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002

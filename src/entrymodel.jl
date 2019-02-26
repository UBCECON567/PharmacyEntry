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
- `α, β, γ, δ` model parameters, see notebooks/pharmacyentry02-model
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

  vars = [s, x..., w...]
  inc = completecases(data[vars])
  S = disallowmissing(data[s][inc])
  X = disallowmissing(convert(Matrix, data[x][inc,:]))
  W = disallowmissing(convert(Matrix, data[w][inc,:]))
  ϵ = rand(distϵ, length(S))
  
  π0 = S.*(X*β) - W*δ + ϵ
  π = similar(π0, length(S), length(α))
  for n in 1:length(α)
    π[:,n] = π0 + S*sum(α[1:n]) .- sum(γ[1:n])
  end
  n = mapslices(x->sum(x.>=0), π, dims=2)
  if (sum(inc) != length(inc)) 
    N = Array{Union{Missing, Integer},1}(undef, nrow(data))
    N .= missing
    N[inc] = n
  else
    N = vec(n)
  end
  return(N)
end

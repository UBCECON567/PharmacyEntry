This project will estimate a model of pharmacy entry similar to
Bresnehan and Reiss (1991). 

This is a work in progress. First part of the assignment is complete. The main pieces are:
 - notesbooks/pharmacyentry01-dataprep.jmd : Weave file containing
   first part of assignment
 - notebooks/pharmacyentry02-model.jmd : Weave file containing second
   part of assignment
 - src/pharmacies.jl : scrapes information on pharmacy addresses from provincial websites in
                       Canada
 - src/census.jl : downloads data on population centres in Canada
 - src/geo.jl : geocodes pharamacies addresses and populations centres to
                facilitate combining
 - src/entrymodel.jl : functions for estimating and simulating the entry model
            

            
 

using Weave
function make(;file="pharmacyentry01-dataprep.jmd", nb = false)
  weave(file,out_path=:doc,
        mod=Main,
        doctype="pandoc2html",
        pandoc_options=["--toc","--toc-depth=2","--filter=pandoc-citeproc"],
        cache=:user)
  if nb
    notebook(file, :pwd, -1, "--allow-errors")
  end
end
#make(nb=true)
make(file="pharmacyentry02-model.jmd", nb=false)

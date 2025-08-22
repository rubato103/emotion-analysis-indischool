# renv removed - using system R packages

# httpgd configuration for VS Code plotting
options(device = function(...) {
  httpgd::hgd()
  .Call("C_hgd_plot_new")
})
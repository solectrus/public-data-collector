# Runs the block with extra ENV values, and restores ENV afterwards.
def with_env(**values, &)
  ClimateControl.modify(**values, &)
end

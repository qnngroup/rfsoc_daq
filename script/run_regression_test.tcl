set test_modules {
  axis_width_converter_test
  axis_differentiator_test
  banked_sample_buffer_test
  buffer_bank_test
  dac_prescaler_test
  dds_test
  lmh6401_spi_test
  sample_discriminator_test
  timetagging_sample_buffer_test
}

# get directory of script
set dir [file dirname [file normalize [info script]]]

# make project
source $dir/make_project.tcl

set_property top regression_test [current_fileset -sims]

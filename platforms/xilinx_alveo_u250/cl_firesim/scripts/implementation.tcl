set impl_run [get_runs impl_1]

reset_runs ${impl_run}

set impl_props [list \
  STEPS.OPT_DESIGN.IS_ENABLED $opt \
  STEPS.PHYS_OPT_DESIGN.IS_ENABLED $phys_opt \
  STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $route_phys_opt \
]

foreach {prop value} [list \
  STEPS.OPT_DESIGN.DIRECTIVE $opt_directive \
  {STEPS.OPT_DESIGN.MORE OPTIONS} $opt_options \
  STEPS.PLACE_DESIGN.DIRECTIVE $place_directive \
  {STEPS.PLACE_DESIGN.MORE OPTIONS} $place_options \
  STEPS.PHYS_OPT_DESIGN.DIRECTIVE $phys_directive \
  {STEPS.PHYS_OPT_DESIGN.MORE OPTIONS} $phys_options \
  STEPS.ROUTE_DESIGN.DIRECTIVE $route_directive \
  {STEPS.ROUTE_DESIGN.MORE OPTIONS} $route_options \
  STEPS.POST_ROUTE_PHYS_OPT_DESIGN.DIRECTIVE $post_phys_directive \
  {STEPS.POST_ROUTE_PHYS_OPT_DESIGN.MORE OPTIONS} $post_phys_options \
] {
  if {$value ne ""} {
    lappend impl_props $prop $value
  }
}

set_property -dict $impl_props ${impl_run}

# Carry the previously approved setting into the actual implementation worker.
set_property STEPS.ROUTE_DESIGN.TCL.PRE ${root_dir}/scripts/xrsight_route_pre.tcl ${impl_run}

if {$route_phys_opt} {
  set run_to_step {phys_opt_design (Post-Route)}
} else {
  set run_to_step route_design
}
launch_runs ${impl_run} -to_step ${run_to_step} -jobs ${jobs}
wait_on_run ${impl_run}
check_progress ${impl_run} "first normal implementation failed"

set WNS [get_property STATS.WNS ${impl_run}]
set WHS [get_property STATS.WHS ${impl_run}]

if {$WNS < 0 || $WHS < 0} {
  open_run ${impl_run}
  report_timing_summary -file ${rpt_dir}/failed_timing_summary.rpt
  report_route_status -file ${rpt_dir}/failed_route_status.rpt
  close_design
  puts "ERROR: did not meet timing; stopped for user review without IDR/ML recovery."
  exit 1
}

puts "INFO: generate bitstream"
launch_runs ${impl_run} -to_step write_bitstream -jobs ${jobs}
wait_on_run ${impl_run}
check_progress ${impl_run} "bitstream generation failed"

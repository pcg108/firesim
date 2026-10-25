# write reports

open_run synth_1

# Report utilization
report_utilization -hierarchical -hierarchical_percentages -file ${rpt_dir}/post_synth_utilization.rpt

# Report control sets
report_control_sets -verbose -file ${rpt_dir}/post_synth_control_sets.rpt

# Report post-synthesis timing for baseline/final comparison
report_timing_summary -delay_type max -max_paths 10 -file ${rpt_dir}/post_synth_timing_summary.rpt
report_timing -delay_type max -max_paths 10 -sort_by group -input_pins -file ${rpt_dir}/post_synth_timing.rpt

# Review actual aggregate utilization before launching placement. No fit retry.
if {[catch {exec python3 ${root_dir}/scripts/l2_perf_resource_gate.py ${rpt_dir}/post_synth_utilization.rpt ${rpt_dir}/post_synth_resource_gate.json} review]} {
  puts $review
  puts "ERROR: synthesis resource review failed; placement was not launched."
  close_design
  exit 1
}
puts $review
close_design

set ml_max_critical_paths 150
set ml_max_strategies 5
set ml_qor_suggestions ${root_dir}/vivado_proj/ml_qor_suggestions.rqs
set ml_strategy_dir ${root_dir}/vivado_proj/ml_strategies

# Vivado 2022.1 built-in IDR flow can fail in report_qor_assessment with a
# bogus huge allocation on this design. Use the explicit QoR-suggestion flow
# used by the older Alveo scripts so timing recovery can continue.
delete_files [list ${ml_qor_suggestions} ${ml_strategy_dir}]

set ml_project_tcls [list]
set ml_rqs_files [list]

open_run ${impl_run}
report_qor_suggestions -max_paths ${ml_max_critical_paths} -max_strategies ${ml_max_strategies} -no_split -quiet
write_qor_suggestions -force -strategy_dir ${ml_strategy_dir} ${ml_qor_suggestions}
close_design

for {set i 1} {$i <= ${ml_max_strategies}} {incr i} {
  set projectTclFile ${root_dir}/vivado_proj/ml_strategies/impl_1Project_MLStrategyCreateRun${i}.tcl
  set nonProjectTclFile ${root_dir}/vivado_proj/ml_strategies/NonProject_MLStrategyCreateRun${i}.tcl

  if {[file exists ${projectTclFile}]} {
    lappend ml_project_tcls ${projectTclFile}
  } elseif {[file exists ${nonProjectTclFile}]} {
    set fh [open ${nonProjectTclFile} r]
    set tclContents [read ${fh}]
    close ${fh}

    if {[regexp {set RQSFile "([^"]+)"} ${tclContents} unused rqsFile] && [file exists ${rqsFile}]} {
      lappend ml_rqs_files ${rqsFile}
    } else {
      puts "WARNING: could not find RQS file in ${nonProjectTclFile}"
    }
  }
}

proc run_project_rqs_strategy { impl_run rqsFile jobs } {
  puts "INFO: using ML RQS strategy from ${rqsFile}"

  add_files -force -fileset utils_1 ${rqsFile}
  reset_runs ${impl_run}

  set_property RQS_FILES ${rqsFile} ${impl_run}
  set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE RQS ${impl_run}
  set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE RQS ${impl_run}
  set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true ${impl_run}
  set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE RQS ${impl_run}
  set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE RQS ${impl_run}

  launch_runs ${impl_run} -to_step route_design -jobs ${jobs}
  wait_on_run ${impl_run}

  check_progress ${impl_run} "implementation failed"

  set WNS [get_property STATS.WNS [get_runs ${impl_run}]]
  set WHS [get_property STATS.WHS [get_runs ${impl_run}]]

  return [list ${WNS} ${WHS}]
}

if {[llength ${ml_project_tcls}] != 0} {
  foreach tclFile ${ml_project_tcls} {
    puts "INFO: using ML strategy from ${tclFile}"
    source ${tclFile}
    set impl_run ${ml_strategy_run}

    launch_runs ${impl_run} -to_step route_design -jobs ${jobs}
    wait_on_run ${impl_run}

    check_progress ${impl_run} "implementation failed"

    set WNS [get_property STATS.WNS [get_runs ${impl_run}]]
    set WHS [get_property STATS.WHS [get_runs ${impl_run}]]

    if {$WNS >= 0 && $WHS >= 0} {
      break
    }
  }
} elseif {[llength ${ml_rqs_files}] != 0} {
  foreach rqsFile ${ml_rqs_files} {
    lassign [run_project_rqs_strategy ${impl_run} ${rqsFile} ${jobs}] WNS WHS

    if {$WNS >= 0 && $WHS >= 0} {
      break
    }
  }
} elseif {[file exists ${ml_qor_suggestions}]} {
  lassign [run_project_rqs_strategy ${impl_run} ${ml_qor_suggestions} ${jobs}] WNS WHS
} else {
  puts "WARNING: no ML strategies or QoR suggestions were generated"
}

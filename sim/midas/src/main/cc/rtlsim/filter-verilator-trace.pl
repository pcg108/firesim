#!/usr/bin/env perl
use strict;
use warnings;

# Verilator compiles trace coverage statically, so keep trace coverage for the
# trafficgen bridge/DPI modules and the ancestors needed to reach target-side
# trafficgen signals that Verilator registers under flattened parent scopes.
# The top.sv $dumpvars calls still select the exact runtime scopes.
my %keep_module = map { $_ => 1 } qw(
  FPGATop
  SimWrapper
  FireSim
  ChipTop
  DigitalTop
  ClockSinkDomain_2
  TrafficGenBridgeModule
  TrafficGenDPIBlackBox
);

my $kept_module = 0;

while (my $line = <STDIN>) {
  if ($line =~ /^module\s+([A-Za-z_][A-Za-z0-9_\$]*)\b/) {
    my $module = $1;
    if ($keep_module{$module}) {
      print "/*verilator tracing_on*/\n";
      $kept_module = 1;
    } else {
      $line =~ s/^module\s+\Q$module\E\b/module $module \/*verilator tracing_off*\/ /;
      $kept_module = 0;
    }
  }

  print $line;

  if ($kept_module && $line =~ /^endmodule\b/) {
    print "/*verilator tracing_off*/\n";
    $kept_module = 0;
  }
}

#!/usr/bin/env perl
use strict;
use warnings;

my ($syms_cpp) = @ARGV;
die "usage: $0 <Vtop__Syms.cpp>\n" unless defined $syms_cpp;

open my $in, '<', $syms_cpp or die "open $syms_cpp: $!";
my $text = do { local $/; <$in> };
close $in;

my $needle = <<'EOF';
        __Vm_dumperp = new VerilatedVcdC();
        __Vm_modelp->trace(__Vm_dumperp, 0, 0);
EOF

my $replacement = <<'EOF';
        __Vm_dumperp = new VerilatedVcdC();
        __Vm_dumperp->dumpvars(99, "TOP.emul.FPGATop");
        __Vm_modelp->trace(__Vm_dumperp, 0, 0);
EOF

my $count = ($text =~ s/\Q$needle\E/$replacement/g);
die "did not patch $syms_cpp\n" unless $count == 1;

open my $out, '>', $syms_cpp or die "write $syms_cpp: $!";
print {$out} $text;
close $out;

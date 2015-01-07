#!/usr/bin/perl

use strict;
use warnings;

package autorandr;
our $XRANDR = '/usr/bin/xrandr';
our $DISPER = '/usr/bin/disper';

our $PROFILES = '~/.autorandr';
our $CONFIG = '~/.autorandr.conf';
our @RESERVED_PROFILE_NAMES = (
	'common      Clone all connected outputs at the largest common resolution',
	'horizontal  Stack all connected outputs horizontally at their largest resolution',
	'vertical    Stack all connected outputs vertically at their largest resolution',
);

our $CURRENT_CFG_METHOD = \&current_cfg_xrandr;

sub current_cfg_xrandr() {
	open(XRANDR_PIPE, "xrandr -q --verbose|");
	my $output = '';
	my $result = '';
	my $disabled = '';
	MAIN: while (<XRANDR_PIPE>) {
		if (/^(\S+) connected (primary)? ?(\d+x\d+)\+(\d+)\+(\d+) (.*)/) {
			##### Found a connected and enabled output
			$output = $1;
			$result .= "output $1\n";
			$result .= "$2\n" if $2;
			# $3 is the transformed resolution, not necessarily the mode resolution
			$result .= "pos $4x$5\n";
			# Now we just need to parse the last parts: rotation+reflection
			$_ = lc $6;
			# Strip off the mode identifier, e.g. "(0x42) "
			s/^(\(0x[0-9a-f]+\)) (.*)/$2/;
			# Strip from "(" to end (available rotations and reflections)
			s/ *\(.*//;
			# Get rotation and reflection specifiers, e.g. "left X and Y axis"
			/^(\w+)? ?((.)( and (.))? axis)?/;
			$result .= ($1) ? "rotate $1\n" : "rotate normal\n";
			$result .= ($2) ? "reflect $3$5\n" : "reflect normal\n";
			next;
		} elsif (/^(\S+) (dis)?connected /) {
			##### Found a disabled output
			$output = '';
			$disabled .= "output $1\noff\n";
		} elsif (/^\S/) {
			##### Not an enabled output
			$output = '';
		}
		next if not $output;
		##### Now parsing lines belonging to the enabled output
		if (/^\s+(\d+x\d+) .* \*current/) {
			##### Found the current output mode resolution
			$result .= "mode $1\n";
			# Refresh rate should be found two lines after
			$_ = <XRANDR_PIPE>;
			$_ = <XRANDR_PIPE>;
			if (/ +v: height .* clock +([\d.]+)(Hz)?/) {
				$result .= "rate $1\n";
			}
			next;
		}
		if (/^\s+Transform: +([\d.]+) ([\d.]+) ([\d.]+)/) {
			##### Found the transformation matrix
			my $transform = "$1,$2,$3";
			my $line2 = <XRANDR_PIPE>;
			my $line3 = <XRANDR_PIPE>;
			my $line4 = <XRANDR_PIPE>;
			foreach $_ ($line2, $line3) {
				if (/^\s+([\d.]+) ([\d.]+) ([\d.]+)/) {
					$transform = "$transform,$1,$2,$3";
				} else {
					# Failed to read the transform matrix
					next MAIN;
				}
			}
			if ($line4 =~ /\s+filter:( none)?\s+$/i) {
				$transform = "none";
			}
			$result .= "transform $transform\n";
			next;
		}
	}
	close(XRANDR_PIPE);
	return ($result, $disabled);
}

sub current_cfg :prototype(;$) {
	##### Usage: current_cfg [include_disabled_outputs]
	##### Disabled outputs are included by default (use 0 or '' to disable)
	my @cfg = &$CURRENT_CFG_METHOD;
	return "$cfg[0]$cfg[1]" if $_[0] or not @_;
	return "$cfg[0]"
}

print current_cfg();

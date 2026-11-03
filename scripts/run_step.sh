#!/usr/bin/env bash
# run_step.sh: run one README step with a timeout and millisecond timing.
# Portable (macOS has no `timeout`); needs only bash and perl.
#
# Usage: run_step.sh <timeout-seconds> '<command exactly as the README says>'
# Prints the command's output, then one summary line:
#   __STEP__ exit=<code> seconds=<1.23> timed_out=<0|1>
# Exit code is the command's, or 124 on timeout (same convention as GNU timeout).

set -u
if [[ $# -lt 2 ]]; then
  echo "usage: run_step.sh <timeout-seconds> '<command>'" >&2
  exit 2
fi

exec perl -MTime::HiRes=time -e '
  my ($limit, $cmd) = @ARGV;
  my $start = time;
  my $pid = fork;
  die "fork failed: $!" unless defined $pid;
  if ($pid == 0) { setpgrp(0, 0); exec "bash", "-c", $cmd; exit 127; }
  my $timed_out = 0;
  local $SIG{ALRM} = sub { $timed_out = 1; kill "TERM", -$pid; sleep 1; kill "KILL", -$pid; };
  alarm $limit;
  my $r;
  do { $r = waitpid($pid, 0) } while ($r == -1 && $!{EINTR});
  my $status = $?;
  alarm 0;
  my $code = $timed_out ? 124 : ($status & 127 ? 128 + ($status & 127) : $status >> 8);
  printf "__STEP__ exit=%d seconds=%.2f timed_out=%d\n", $code, time - $start, $timed_out;
  exit $code;
' "$1" "$2"

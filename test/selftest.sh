#!/usr/bin/env bash
# qci.sh's own checks: each case builds a throwaway project and asserts on qci's exit code and what it wrote.
set -uo pipefail
QCI=$(cd "$(dirname "$0")/.." && pwd)/qci.sh
PQ=${PEACHQ_Q:?set PEACHQ_Q to a peachq q}
PQ=$(cd "$(dirname "$PQ")" && pwd)/$(basename "$PQ")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

fail() { echo "FAIL $*"; sed 's/^/     /' "$work/out"; fails=$((fails + 1)); }
# expect <exit code> <name> <command...>: runs it with no engine or QCI_* variable set unless the command sets one
expect() {
  local want=$1 name=$2 rc
  shift 2
  env -u PEACHQ_Q -u KX_Q -u KORZE_Q -u L_Q -u QCMD -u QHOME -u QCI_ENTRY -u QCI_TESTS -u QCI_JUNIT -u QCI_TIMEOUT \
    "$@" > "$work/out" 2>&1
  rc=$?
  if [ "$rc" = "$want" ]; then echo "ok   $name"; else fail "$name: exit $rc, wanted $want"; fi
}
has() { grep -qF -- "$2" "$1" || fail "$1 lacks: $2"; }
project() { rm -rf "$work/p"; mkdir -p "$work/p"; cd "$work/p" || exit 2; printf '%s\n' "$@" > .qci; }

project 'QCI_ENTRY=ok.q'
echo 'a:1;' > ok.q
expect 0 "a file that loads passes" PEACHQ_Q="$PQ" "$QCI"
has qci-results/peachq.csv '"load:ok.q","pass",""'
has qci-results/peachq.id 'args=-classic'

expect 0 "QCMD naming peachq fills the peachq slot" QCMD="$PQ" "$QCI"
has qci-results/peachq.id 'label=peachq (QCMD)'

mkdir -p "$work/bin" && ln -sf "$PQ" "$work/bin/q"
expect 0 "with nothing named, peachq is found on PATH" PATH="$work/bin:$PATH" "$QCI"
has qci-results/peachq.id 'label=peachq (found at'

expect 0 "PEACHQ_ARGS replaces -classic" PEACHQ_Q="$PQ" PEACHQ_ARGS= "$QCI"
has qci-results/peachq.id 'args='
grep -q 'args=-classic' qci-results/peachq.id && fail "PEACHQ_ARGS= still ran -classic"

expect 2 "an unknown engine is refused" PEACHQ_Q="$PQ" "$QCI" banana
expect 2 "a requested engine that is not there is refused" HOME="$work" PEACHQ_Q="$PQ" "$QCI" kx
has "$work/out" 'engine kx: not found'

rm .qci
expect 2 "nothing configured is refused" PEACHQ_Q="$PQ" "$QCI"
has "$work/out" 'nothing to check'

project 'QCI_ENTRY=bad.q'
echo '1+`a;' > bad.q
expect 1 "a load error fails, with its error" PEACHQ_Q="$PQ" "$QCI"
has qci-results/peachq.csv '"load:bad.q","fail","'"'"'type"'
echo 'load:bad.q  # peachq-lacks: an example gap' > qci-known-gaps.txt
expect 0 "a listed known gap passes" PEACHQ_Q="$PQ" "$QCI"
echo 'a:1;' > bad.q
expect 1 "a listed known gap that passes now fails" PEACHQ_Q="$PQ" "$QCI"
has "$work/out" 'now passes: load:bad.q'

project 'QCI_TESTS=cp cases.xml out.xml; exit 1' 'QCI_JUNIT=out.xml'
printf '%s\n' '<testsuites><testsuite name="s">' '<testcase classname="t" name="good"/>' \
  '<testcase classname="t" name="bad"><failure message="1 &lt;&gt; 2"/></testcase>' \
  '<testcase classname="t" name="bad"/>' '<testcase classname="t" name="later"><skipped/></testcase>' \
  '</testsuite></testsuites>' > cases.xml
expect 1 "a failing JUnit test fails" PEACHQ_Q="$PQ" "$QCI"
has qci-results/peachq.csv '"test:t.bad","fail","1 <> 2"'
has qci-results/peachq.csv '"test:t.bad~2","pass",""'
has qci-results/peachq.csv '"test:t.later","skip",""'
echo 'test:t.bad  # tree-bug: an example' > qci-known-gaps.txt
expect 0 "a listed failing test explains the failing tests row" PEACHQ_Q="$PQ" "$QCI"
echo '<testsuite>' > cases.xml
expect 1 "an unreadable JUnit report fails" PEACHQ_Q="$PQ" "$QCI"
has qci-results/peachq.csv '"junit","error","unreadable JUnit XML'

project 'QCI_TESTS=exit 0' 'QCI_JUNIT=never.xml'
expect 1 "a JUnit report that was never written fails" PEACHQ_Q="$PQ" "$QCI"
has qci-results/peachq.csv '"junit","error","the tests wrote no never.xml"'

project 'QCI_TIMEOUT=2' "QCI_TESTS=bash -c 'trap \"\" TERM; sleep 60' & sleep 60"
start=$(date +%s)
expect 1 "a hung test times out, children and all" PEACHQ_Q="$PQ" "$QCI"
[ $(($(date +%s) - start)) -lt 20 ] || fail "the timeout took $(($(date +%s) - start))s"
has qci-results/peachq.csv '"tests","timeout","no answer in 2s"'
echo 'tests  # tree-bug: listed, but a timeout is never a known gap' > qci-known-gaps.txt
expect 1 "a known gap never hides a timeout" PEACHQ_Q="$PQ" "$QCI"

long=$(printf 'x%.0s' $(seq 1 3000))
project 'QCI_TESTS=cp "$QCI_ENGINE.xml" out.xml' 'QCI_JUNIT=out.xml'
printf '<testsuite><testcase name="%s"/></testsuite>\n' "$long" > l.xml
printf '<testsuite><testcase name="%s"><failure message="no"/></testcase></testsuite>\n' "$long" > peachq.xml
echo "test:$long  # tree-bug: a long name" > qci-known-gaps.txt
printf '#!/bin/sh\nexec "%s" "$@"\n' "$PQ" > "$work/other-q" && chmod +x "$work/other-q"
expect 0 "a long test name runs" PEACHQ_Q="$PQ" L_Q="$work/other-q" "$QCI"
expect 0 "a long test name still gives one short link" "$QCI" compare
url=$(grep -o 'https://github.com/peachq-org/peachq/issues/new[^)]*' "$work/out")
[ "$(printf '%s\n' "$url" | wc -l | tr -d ' ')" = 1 ] && [ ${#url} -lt 7000 ] || fail "link: ${#url} characters"

project 'QCI_ENTRY=ok.q' 'QCI_TESTS=[ "$QCI_ENGINE" != peachq ]'
echo 'a:1;' > ok.q
echo 'tests  # tree-bug: this fixture fails on purpose' > qci-known-gaps.txt
expect 0 "two engines run, alphabetically" PEACHQ_Q="$PQ" L_Q="$work/other-q" "$QCI"
has qci-results/l.csv '"tests","pass",""'
has qci-results/peachq.csv '"tests","fail","exit 1"'
expect 0 "compare tabulates both and links the difference" GITHUB_STEP_SUMMARY="$work/summary" "$QCI" compare
has "$work/out" '| check | l | peachq |'
has "$work/out" '| tests | pass | fail: exit 1 (known gap) |'
has "$work/out" 'https://github.com/peachq-org/peachq/issues/new?template=compat.yml&title=Compatibility%3A%20tests%20differs%20from%20l'
has "$work/out" '&check=tests&engines='
has "$work/summary" '## q checks by engine'
[ "$(grep -c 'report to peachq' "$work/out")" = 1 ] || fail "one difference should give exactly one link"

echo
[ $fails = 0 ] && echo "selftest: all ok" || echo "selftest: $fails failed"
exit $((fails > 0))

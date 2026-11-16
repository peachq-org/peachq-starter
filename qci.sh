#!/usr/bin/env bash
# qci: run a q project's checks on one or more q engines, and compare them. See README.md.
set -uo pipefail

SLOTS="kx korze l peachq"
RESULTS=$PWD/qci-results
KNOWN_GAPS=qci-known-gaps.txt
REPORT_URL=https://github.com/peachq-org/peachq/issues/new
TAB=$(printf '\t')
CHILD=

say() { printf 'qci: %s\n' "$*" >&2; }
die() { say "$*"; exit 2; }

usage() {
  cat <<'EOF'
usage: qci.sh [engine ...]   run the checks: no engine = every engine named by its variable (peachq if none)
       qci.sh all            run every engine that can be found, named or discovered
       qci.sh compare        tabulate qci-results/ by engine, apply the known gaps, link differences to report
engines: peachq (PEACHQ_Q) kx (KX_Q) korze (KORZE_Q) l (L_Q), q (QCMD, when it is not peachq), path (q on PATH)
config (env, or KEY=VALUE lines in .qci): QCI_ENTRY QCI_TESTS QCI_TIMEOUT QCI_JUNIT, <ENGINE>_ARGS
EOF
}

load_config() {
  local line k v
  [ -f .qci ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|'#'*) continue ;; esac
    k=${line%%=*} v=${line#*=}
    case $k in
      QCI_ENTRY|QCI_TESTS|QCI_TIMEOUT|QCI_JUNIT|PEACHQ_ARGS|KX_ARGS|KORZE_ARGS|L_ARGS|QCMD_ARGS|PATH_ARGS) ;;
      *) die ".qci: unknown key '$k' (engine binaries are machine-specific: set them in the environment)" ;;
    esac
    if [ -z "${!k+x}" ]; then printf -v "$k" '%s' "$v"; export "${k?}"; fi
  done < .qci
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
slot_var() { case $1 in q) echo QCMD ;; path) ;; *) echo "$(upper "$1")_Q" ;; esac; }
engine_args() {
  local v
  case $1 in
    peachq) printf '%s' "${PEACHQ_ARGS--classic}"; return ;;
    q) v=QCMD_ARGS ;;
    *) v=$(upper "$1")_ARGS ;;
  esac
  printf '%s' "${!v:-}"
}

# run_bounded <seconds> <log> <command...>: the command runs in a process group of its own, which a timeout kills
# whole (TERM, then KILL); a timeout answers 124
run_bounded() {
  local secs=$1 log=$2 rc dog
  shift 2
  rm -f "$log.timeout"
  set -m
  "$@" > "$log" 2>&1 < /dev/null &
  CHILD=$!
  (sleep "$secs"; : > "$log.timeout"; kill -TERM -- -"$CHILD"; sleep 5; kill -KILL -- -"$CHILD") > /dev/null 2>&1 &
  dog=$!
  set +m
  wait "$CHILD" 2> /dev/null; rc=$?
  kill -KILL -- -"$dog" 2> /dev/null
  wait "$dog" 2> /dev/null
  kill -KILL -- -"$CHILD" 2> /dev/null
  CHILD=
  if [ -e "$log.timeout" ]; then rm -f "$log.timeout"; return 124; fi
  return $rc
}
trap '[ -z "$CHILD" ] || kill -KILL -- -"$CHILD" 2> /dev/null; exit 130' INT TERM

probe_script() {
  [ -f "$RESULTS/.probe.q" ] && return
  cat > "$RESULTS/.probe.q" <<'EOF'
-1 "qci-pq=",string 10h=type @[value;`.pq.version;0];
-1 "qci-zK=",@[{string value x};`.z.K;""];
-1 "qci-zk=",@[{string value x};`.z.k;""];
-1 "qci-zv=",@[{$[99h=type v:value x;$[`version in key v;v`version;-3!v];10h=type v;v;-3!v]};`.z.v;""];
exit 0
EOF
}

# probe <binary>: its identity lines (qci-pq= qci-zK= qci-zk= qci-zv=), cached by path, run without engine args
probe() {
  local key
  key=$RESULTS/.probe-$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  if [ ! -f "$key" ]; then
    probe_script
    run_bounded 30 "$key.log" "$1" "$RESULTS/.probe.q"
    grep '^qci-' "$key.log" > "$key"
  fi
  cat "$key"
}
is_peachq() { probe "$1" | grep -qx 'qci-pq=1'; }

host_qdir() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo l64 ;;
    Linux-aarch64|Linux-arm64) echo l64arm ;;
    Darwin-*) echo m64 ;;
    MINGW*|MSYS*|CYGWIN*) echo w64 ;;
  esac
}

executable() {
  local p
  p=$(command -v -- "$1" 2> /dev/null) || return 1
  [ -f "$p" ] && [ -x "$p" ] || return 1
  (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$p")")
}

# resolve <engine> [search]: sets BIN and LABEL. A set variable is trusted as labelled; only a binary found by
# searching is probed, and a peachq found anywhere fills the peachq slot, never another
resolve() {
  local var c qd
  BIN= LABEL=
  var=$(slot_var "$1")
  if [ -n "$var" ] && [ -n "${!var:-}" ]; then
    BIN=$(executable "${!var}") || die "$var=${!var} is not an executable file"
    LABEL="$1 ($var)"
    [ "$1" != q ] || { ! is_peachq "$BIN" || return 1; LABEL="q (QCMD)"; }
    return 0
  fi
  if [ "$1" = peachq ] && [ -n "${QCMD:-}" ] && BIN=$(executable "$QCMD") && is_peachq "$BIN"; then
    LABEL="peachq (QCMD)"
    return 0
  fi
  BIN=
  [ "${2:-}" = search ] || return 1
  qd=$(host_qdir)
  case $1 in
    peachq)
      for c in q ${QHOME:+"$QHOME/$qd/q"} "$HOME/q/$qd/q"; do
        c=$(executable "$c") && is_peachq "$c" && { BIN=$c LABEL="peachq (found at $c)"; return 0; }
      done ;;
    kx)
      [ -n "$qd" ] && for c in ${QHOME:+"$QHOME/$qd/q"} "$HOME/q/$qd/q"; do
        c=$(executable "$c") && ! is_peachq "$c" && { BIN=$c LABEL="q on QHOME"; return 0; }
      done ;;
    path)
      c=$(executable q) && ! is_peachq "$c" && { BIN=$c LABEL="q on PATH"; return 0; } ;;
  esac
  return 1
}

select_engines() {
  local e named=
  ENGINES=
  case "${1:-}" in
    all) for e in $SLOTS path q; do resolve "$e" search && ENGINES="$ENGINES $e"; done ;;
    '')
      for e in $SLOTS q; do resolve "$e" && ENGINES="$ENGINES $e" && named=1; done
      [ -n "$named" ] || { resolve peachq search && ENGINES=peachq; } ||
        die "no q engine: set PEACHQ_Q, use peachq-org/setup-peachq, or put peachq on PATH"
      ;;
    *)
      for e in "$@"; do
        case " $SLOTS path q " in *" $e "*) ;; *) die "unknown engine '$e'" ;; esac
        resolve "$e" search || die "engine $e: not found"
        ENGINES="$ENGINES $e"
      done ;;
  esac
  ENGINES=$(printf '%s\n' $ENGINES | sort -u | paste -sd' ' -)
  dedupe
  [ -n "$ENGINES" ] || die "no q engine found"
}

dedupe() {
  local e seen= kept=
  for e in $ENGINES; do
    resolve "$e" search
    case "$seen" in *"|$BIN|"*) say "$e is the same binary as an engine already selected; skipped"; continue ;; esac
    seen="$seen|$BIN|" kept="$kept $e"
  done
  ENGINES=${kept# }
}

clean() {
  local s
  s=$(printf '%s' "$1" | tr '\t\r\n' '   ')
  s=${s:0:500}
  s=${s//"$PWD"/.}
  printf '%s' "${s//"$HOME"/"~"}"
}
csvq() { printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')"; }
row() { printf '%s,%s,%s\n' "$(csvq "$2")" "$(csvq "$3")" "$(csvq "$(clean "$4")")" >> "$RESULTS/$1.csv"; }

# rows <engine>: the engine's results as check<TAB>status<TAB>message
rows() {
  awk 'NR > 1 {
    n = 0; f = ""; q = 0
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (q && c == "\"" && substr($0, i + 1, 1) == "\"") { f = f c; i++ }
      else if (c == "\"") q = !q
      else if (!q && c == ",") { out[++n] = f; f = "" }
      else f = f c
    }
    out[++n] = f
    print out[1] "\t" out[2] "\t" out[3]
  }' "$RESULTS/$1.csv"
}

qstr() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }

run_loads() {
  local e=$1 n=0 entry dir file drv log rc msg old_ifs=$IFS
  IFS=,
  set -- $QCI_ENTRY
  IFS=$old_ifs
  for entry; do
    n=$((n + 1)) dir=. file=$entry
    case $entry in *:*) dir=${entry%%:*} file=${entry#*:} ;; esac
    if [ ! -f "$dir/$file" ]; then row "$e" "load:$entry" fail "$entry not found"; continue; fi
    drv=$RESULTS/.load-$n.q log=$RESULTS/$e-load-$n.log
    printf '@[system;"l %s";{-1 "qci-load-error: ",x; exit 3}];\n-1 "qci-load-ok";\nexit 0\n' "$(qstr "$file")" > "$drv"
    run_bounded "$TIMEOUT" "$log" bash -c 'cd "$1" && shift && exec "$@"' - "$dir" "$WRAP" "$drv"; rc=$?
    if [ $rc = 0 ] && grep -q '^qci-load-ok' "$log"; then row "$e" "load:$entry" pass ""
    elif [ $rc = 124 ]; then row "$e" "load:$entry" timeout "no answer in ${TIMEOUT}s"
    elif msg=$(grep -m1 '^qci-load-error: ' "$log"); then row "$e" "load:$entry" fail "'${msg#qci-load-error: }"
    else row "$e" "load:$entry" fail "exit $rc: $(grep -m1 . "$log")"
    fi
  done
}

junit_rows() {
  python3 -I - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    cases = list(ET.parse(sys.argv[1]).getroot().iter("testcase"))
except Exception as e:
    sys.exit("unreadable JUnit XML: %s" % e)
if not cases:
    sys.exit("no <testcase> in the JUnit XML")
seen = {}
kinds = (("failure", "fail"), ("error", "error"), ("skipped", "skip"))
for c in cases:
    cls, name = c.get("classname", ""), c.get("name", "")
    key = cls + "." + name if cls else name
    seen[key] = seen.get(key, 0) + 1
    if seen[key] > 1:
        key += "~%d" % seen[key]
    status, msg = "pass", ""
    for tag, kind in kinds:
        el = c.find(tag)
        if el is not None:
            status, msg = kind, el.get("message") or (el.text or "").strip()
            break
    print("test:%s\t%s\t%s" % (" ".join(key.split()), status, " ".join(msg.split())))
PY
}

run_tests() {
  local e=$1 log=$RESULTS/$1-tests.log rc out
  [ -z "${QCI_JUNIT:-}" ] || rm -f "$QCI_JUNIT"
  run_bounded "$TIMEOUT" "$log" env QCMD="$WRAP" QCI_ENGINE="$e" bash -c "$QCI_TESTS"; rc=$?
  case $rc in
    0) row "$e" tests pass "" ;;
    124) row "$e" tests timeout "no answer in ${TIMEOUT}s" ;;
    *) if [ $rc -lt 124 ]; then row "$e" tests fail "exit $rc"; else row "$e" tests error "exit $rc"; fi ;;
  esac
  [ -n "${QCI_JUNIT:-}" ] || return 0
  if [ ! -s "$QCI_JUNIT" ]; then row "$e" junit error "the tests wrote no $QCI_JUNIT"
  elif ! command -v python3 > /dev/null; then row "$e" junit error "python3 is needed to read $QCI_JUNIT"
  elif out=$(junit_rows "$QCI_JUNIT" 2>&1); then
    cp "$QCI_JUNIT" "$RESULTS/$e-junit.xml"
    printf '%s\n' "$out" | while IFS=$TAB read -r c s m; do row "$e" "$c" "$s" "$m"; done
  else row "$e" junit error "$out"
  fi
}

run_engine() {
  local e=$1 args a
  resolve "$e" search
  args=$(engine_args "$e")
  WRAP=$RESULTS/.bin/$e
  mkdir -p "$RESULTS/.bin"
  { echo '#!/usr/bin/env bash'; printf 'exec %q "$@"' "$BIN"; for a in $args; do printf ' %q' "$a"; done; echo; } > "$WRAP"
  chmod +x "$WRAP"
  { echo "label=$LABEL"; echo "binary=$(clean "$BIN")"; echo "args=$args"; probe "$BIN" | sed 's/^qci-//'; } > "$RESULTS/$e.id"
  echo "check,status,message" > "$RESULTS/$e.csv"
  say "$LABEL: $BIN $args"
  [ -z "${QCI_ENTRY:-}" ] || run_loads "$e"
  [ -z "${QCI_TESTS:-}" ] || run_tests "$e"
}

gaps_file() { if [ "$1" = peachq ]; then echo "$KNOWN_GAPS"; else echo "qci-known-gaps-$1.txt"; fi; }
known_gaps() {
  local f
  f=$(gaps_file "$1")
  [ -f "$f" ] || return 0
  sed -e 's/ #.*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^platform:/d' -e '/^$/d' "$f"
}

# table: every result as engine<TAB>check<TAB>status<TAB>message<TAB>known-gap(0|1)
table() {
  local e
  for e in $1; do
    known_gaps "$e" > "$RESULTS/.gaps-$e"
    rows "$e" | awk -F'\t' -v e="$e" -v g="$RESULTS/.gaps-$e" '
      BEGIN { while ((getline l < g) > 0) gap[l] = 1 }
      { print e "\t" $1 "\t" $2 "\t" $3 "\t" (($1 in gap) ? 1 : 0) }'
  done
}

# verdict <engine>: one line per unexplained result. Known gaps hold both ways; a failing tests row is explained
# by the per-test rows when it exited normally and one of them failed
verdict() {
  local f
  f=$(gaps_file "$1")
  { known_gaps "$1" | sed "s/^/gap$TAB/"; rows "$1" | sed "s/^/row$TAB/"; } | awk -F'\t' -v f="$f" '
    $1 == "gap" { gap[$2] = 1; next }
    { st[$2] = $3; msg[$2] = $4; order[++n] = $2; if ($2 ~ /^test:/ && $3 != "pass" && $3 != "skip") testfail = 1 }
    END {
      for (i = 1; i <= n; i++) {
        c = order[i]; bad = st[c] != "pass" && st[c] != "skip"
        if (c == "tests" && st[c] == "fail" && testfail) continue
        if (bad && !(c in gap)) print "unexpected " st[c] ": " c (msg[c] == "" ? "" : " - " msg[c])
        if (!bad && (c in gap)) print "now passes: " c " - remove it from " f
      }
    }'
}

report() {
  local v n
  v=$(verdict "$1")
  n=$(rows "$1" | wc -l | tr -d ' ')
  if [ -z "$v" ]; then say "$1: ok ($n checks)"; return 0; fi
  say "$1: FAILED ($n checks)"
  printf '%s\n' "$v" | sed 's/^/  /' >&2
  return 1
}

urlencode() {
  local LC_ALL=C s=$1 i c n out=
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9._~-]) out+=$c ;;
      *) printf -v n '%d' "'$c"; printf -v c '%%%02X' $(((n + 256) % 256)); out+=$c ;;
    esac
  done
  printf '%s' "$out"
}

idfield() { sed -n "s/^$2=//p" "$RESULTS/$1.id" 2> /dev/null; }

# report_link <all.tsv> <check> <other engine...>: a prefilled compat issue form holding the check, each engine's
# result and identity - never source - cut to stay under 7000 characters
report_link() {
  local all=$1 check=$2 e st engines= other= mine= cap=4000 url
  shift 2
  for e in peachq "$@"; do
    engines="$engines$e: $(idfield "$e" label); .z.K=$(idfield "$e" zK) .z.k=$(idfield "$e" zk) .z.v=$(idfield "$e" zv); args=$(idfield "$e" args)
"
    st=$(awk -F'\t' -v e="$e" -v c="$check" '$1 == e && $2 == c { print $3 ($4 == "" ? "" : ": " $4); f = 1 }
      END { if (!f) print "not run" }' "$all")
    if [ "$e" = peachq ]; then mine=$st; else other="$other$e: $st
"; fi
  done
  while :; do
    url="$REPORT_URL?template=compat.yml&title=$(urlencode "Compatibility: $check differs from $*")"
    url="$url&check=$(urlencode "$check")&engines=$(urlencode "$(cut_to $cap "$engines")")"
    url="$url&other=$(urlencode "$(cut_to $cap "$other")")&peachq=$(urlencode "$(cut_to $cap "$mine")")"
    [ ${#url} -lt 7000 ] && break
    cap=$((cap / 2))
  done
  printf '%s' "$url"
}
cut_to() {
  if [ ${#2} -le "$1" ]; then printf '%s' "$2"; return; fi
  printf '%s\n(cut short by qci to keep this link under 7000 characters; the CI log has it all)' "${2:0:$1}"
}

compare() {
  local engines e all diffs check others problems=0 out
  engines=$( (cd "$RESULTS" 2> /dev/null && ls -- *.csv 2> /dev/null) | sed 's/\.csv$//' | sort | paste -sd' ' -)
  [ -n "$engines" ] || die "nothing to compare: run qci.sh first"
  all=$RESULTS/.all.tsv diffs=$RESULTS/.diffs.tsv out=$RESULTS/compare.md
  table "$engines" > "$all"
  {
    awk -F'\t' -v engines="$engines" -v diffs="$diffs" '
      function cell(s) { gsub(/\|/, "\\|", s); return s }
      { k = $1 SUBSEP $2; st[k] = $3; msg[k] = $4; gap[k] = $5; if (!($2 in seen)) { seen[$2] = 1; C[++nc] = $2 } }
      END {
        ne = split(engines, E, " ")
        printf "## q checks by engine\n\n| check |"; for (j = 1; j <= ne; j++) printf " %s |", E[j]
        printf "\n|---|"; for (j = 1; j <= ne; j++) printf "---|"; print ""
        for (i = 1; i <= nc; i++) {
          c = C[i]; printf "| %s |", cell(c); others = ""
          for (j = 1; j <= ne; j++) {
            k = E[j] SUBSEP c
            v = (k in st) ? st[k] (msg[k] == "" ? "" : ": " msg[k]) (gap[k] ? " (known gap)" : "") : "-"
            printf " %s |", cell(v)
            cmp[E[j]] = (k in st) ? st[k] (st[k] == "pass" ? "" : " " msg[k]) : "-"
          }
          print ""
          if (!("peachq" in cmp)) continue
          for (j = 1; j <= ne; j++) if (E[j] != "peachq" && cmp[E[j]] != cmp["peachq"]) others = others " " E[j]
          if (others != "") print c "\t" substr(others, 2) > diffs
        }
      }' "$all"
    printf '\n| engine | label | .z.K | .z.k | .z.v | args |\n|---|---|---|---|---|---|\n'
    for e in $engines; do
      printf '| %s | %s | %s | %s | %s | %s |\n' "$e" "$(idfield "$e" label)" "$(idfield "$e" zK)" \
        "$(idfield "$e" zk)" "$(idfield "$e" zv)" "$(idfield "$e" args)"
    done
    if [ -s "$diffs" ]; then
      printf '\n### Where peachq differs\n\nEach link opens a prefilled peachq issue for you to review; nothing is sent until you submit it.\n\n'
      while IFS=$TAB read -r check others; do
        printf -- '- %s: [report to peachq](%s)\n' "$check" "$(report_link "$all" "$check" $others)"
      done < "$diffs"
    fi
  } > "$out"
  rm -f "$diffs"
  cat "$out"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || cat "$out" >> "$GITHUB_STEP_SUMMARY"
  for e in $engines; do report "$e" || problems=1; done
  return $problems
}

main() {
  local e problems=0
  case "${1:-}" in -h|--help) usage; exit 0 ;; compare) compare; exit $? ;; esac
  load_config
  [ -n "${QCI_ENTRY:-}${QCI_TESTS:-}" ] || die "nothing to check: set QCI_ENTRY and/or QCI_TESTS (env or .qci)"
  TIMEOUT=${QCI_TIMEOUT:-300}
  case $TIMEOUT in ''|*[!0-9]*) die "QCI_TIMEOUT must be whole seconds" ;; esac
  rm -rf "$RESULTS"
  mkdir -p "$RESULTS"
  select_engines "$@"
  for e in $ENGINES; do run_engine "$e"; done
  for e in $ENGINES; do report "$e" || problems=1; done
  exit $problems
}

main "$@"

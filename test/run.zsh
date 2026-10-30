#!/usr/bin/env zsh
# hrdrcfg's tests: each runs bin/hrdrcfg against a stand-in herdr-app that
# records every call, in a throwaway project, and never touches a real window.

emulate -R zsh
setopt no_unset pipe_fail

HERE=${0:A:h}
HRDRCFG=$HERE:h/bin/hrdrcfg
TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT

passed=0 failed=0
pass() { (( passed++ )); print -r -- "ok    $1"; }
fail() { (( failed++ )); print -r -- "FAIL  $1"; [[ -n ${2:-} ]] && print -r -- "      $2"; }
check() { local name=$1 want=$2 got=$3; [[ $got == $want ]] && pass $name || fail $name "want: ${(q+)want}  got: ${(q+)got}"; }

# The stand-in: logs `do` calls one per line as JSON, answers `ls` from $STUB_LS.
STUB=$TMP/herdr-app
cat >$STUB <<'EOF'
#!/usr/bin/env zsh
case $1 in
  ls) cat $STUB_LS ;;
  do)
    shift
    print -rl -- "$@" | jq -R . | jq -sc . >>$STUB_LOG
    case $1 in
      space.new) print '{"space":"sp-new","tab":"tb-1","terminal":"t1"}' ;;
      tab.new)   print '{"tab":"tb-n","terminal":"tn"}' ;;
      *)         print '{"ok":true}' ;;
    esac ;;
esac
EOF
chmod +x $STUB
export HRDRCFG_HERDR=$STUB STUB_LOG=$TMP/calls STUB_LS=$TMP/ls.json

# A project, the user's config, and one user's override.
PROJ=$TMP/prj/Demo
mkdir -p $PROJ/.hrdrcfg
export HRDRCFG_CONFIG=$TMP/config.yaml
cat >$HRDRCFG_CONFIG <<'EOF'
roles_cmd: printf 'cc\nhv\nvc\nzz\ndc\n' | grep -v '^hv$'
roles_order: [vc, dc, ic, cc]
tabs:
  - sh
roots: [ROOTS]
EOF
sed -i '' "s|ROOTS|$TMP/prj|" $HRDRCFG_CONFIG 2>/dev/null || sed -i "s|ROOTS|$TMP/prj|" $HRDRCFG_CONFIG
print 'space: devel/demo' >$PROJ/.hrdrcfg/dft.hrdrcfg
cat >$PROJ/.hrdrcfg/$USER.hrdrcfg <<'EOF'
tabs:
  - sh
  - name: outs
    run: intent expl outs
EOF

no_spaces() { print '{"spaces":[]}' >$STUB_LS; }
open_demo() {
  jq -n '{spaces: [{id: "sp-demo", name: "devel/demo", tabs: [
    {name: "vc", terminals: [{terminal: "t1", app: '"$1"'}]},
    {name: "sh", terminals: [{terminal: "t2", app: null}]}]}]}' >$STUB_LS
}
calls() { [[ -f $STUB_LOG ]] && jq -r ".[0]" $STUB_LOG; }
reset() { rm -f $STUB_LOG; }

# Roles in roles_order first, then the rest as printed; the user's tabs replace the list whole.
want_tabs=(vc dc cc zz sh outs)
got=$(cd $PROJ && $HRDRCFG show | awk '$1 == "tab" {print $2}')
check "show: roles ordered, then tabs; user file layered over dft" "${(F)want_tabs}" "$got"

check "show: space name from dft" "devel/demo" "$(cd $PROJ && $HRDRCFG show | awk '$1 == "space" {print $2}')"

# Found from a subfolder, as git finds its root.
mkdir -p $PROJ/sub/deeper
check "show: root found from a subfolder" "devel/demo" "$(cd $PROJ/sub/deeper && $HRDRCFG show | awk '$1 == "space" {print $2}')"

# up on a closed space: space.new with the first tab, then tab.new for each of the rest, in order.
no_spaces; reset
(cd $PROJ && $HRDRCFG up >/dev/null)
first=$(jq -r 'select(.[0] == "space.new") | .[index("--tab") + 1]' $STUB_LOG)
rest=$(jq -r 'select(.[0] == "tab.new") | .[index("--name") + 1]' $STUB_LOG)
check "up: space.new carries the first tab" $want_tabs[1] "$first"
check "up: tab.new for every other tab, in order" "${(F)want_tabs[2,-1]}" "$rest"
check "up: every tab starts in the project root" "$PROJ" \
  "$(jq -r '.[index("--folder") + 1]' $STUB_LOG | sort -u)"
check "up: run line becomes argv words" '["intent","expl","outs"]' \
  "$(jq -c 'select(.[0] == "tab.new" and .[index("--name") + 1] == "outs") | .[index("--argv") + 1] | fromjson' $STUB_LOG)"

# up on an open space: shown, nothing built.
open_demo null; reset
(cd $PROJ && $HRDRCFG up >/dev/null)
check "up: an open space is only selected" "space.select" "$(calls)"

# down with an agent running: refused without --yes when not asked on a tty, closed with it.
open_demo '"claude-code"'; reset
(cd $PROJ && $HRDRCFG down </dev/null >/dev/null 2>&1)
check "down: refuses while an agent runs" "" "$(calls)"
(cd $PROJ && $HRDRCFG down --yes >/dev/null)
check "down: --yes closes it" "space.close" "$(calls)"

open_demo null; reset
(cd $PROJ && $HRDRCFG down </dev/null >/dev/null)
check "down: no agents, closes without asking" "space.close" "$(calls)"

# ls: every project under the roots, open or closed.
open_demo null
mkdir -p $TMP/prj/Other/.hrdrcfg
got=$($HRDRCFG ls | awk '{print $1, $2}' | sort)
check "ls: projects under roots, with state" $'closed other\nopen devel/demo' "$got"

# A run that is neither a line nor a list is refused.
cat >$PROJ/.hrdrcfg/$USER.hrdrcfg <<'EOF'
tabs:
  - name: bad
    run: {not: a command}
EOF
(cd $PROJ && $HRDRCFG show >/dev/null 2>&1) && fail "show: a malformed run is refused" || pass "show: a malformed run is refused"

# init writes a starter that show can read.
INIT=$TMP/prj/Fresh
mkdir -p $INIT
(cd $INIT && $HRDRCFG init >/dev/null)
check "init: starter names the space after the folder" "fresh" "$(cd $INIT && $HRDRCFG show | awk '$1 == "space" {print $2}')"

check "--version reads VERSION" "hrdrcfg $(<$HERE:h/VERSION)" "$($HRDRCFG --version)"

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))

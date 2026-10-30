#!/usr/bin/env zsh
# hrdrcfg's tests: each runs bin/hrdrcfg against a stand-in herdr-app that
# records every call, in a throwaway project, and never touches a real window.

emulate -R zsh
setopt no_unset pipe_fail

HERE=${0:A:h}
HRDRCFG=$HERE:h/bin/hrdrcfg
TMP=${$(mktemp -d):A}
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
# Never the real ~/.config/hrdrcfg/spaces.
export HRDRCFG_SPACES=$TMP/spaces

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

# --- 0.2.0: spaces/ files, a folder per tab, another machine, discover -----------

# A stand-in hc: `get` answers a terminal's cwd from $STUB_CWDS; `exec` is the remote home.
HCSTUB=$TMP/hc
cat >$HCSTUB <<'EOF'
#!/usr/bin/env zsh
case $1 in
  get)  jq -cn --arg a $2 --arg c "$(jq -r --arg a $2 '.[$a] // empty' $STUB_CWDS)" '{address: $a, cwd: $c}' ;;
  exec) print -n /home/u ;;
esac
EOF
chmod +x $HCSTUB
export HRDRCFG_HC=$HCSTUB STUB_CWDS=$TMP/cwds.json
print '{}' >$STUB_CWDS
mkdir -p $HRDRCFG_SPACES

# A space that is not a project, on another machine, with a folder for one tab.
cat >$HRDRCFG_SPACES/box.hrdrcfg <<'EOF'
space: me@box
machine: box
folder: ~/agt
roles_cmd: ""
tabs:
  - name: box-sysadm
    folder: box-sysadm
  - term
EOF
no_spaces; reset
$HRDRCFG up me@box >/dev/null
check "up: a spaces/ file is found by its space name" "me@box" "$(jq -r 'select(.[0] == "space.new") | .[index("--name") + 1]' $STUB_LOG)"
check "up: a remote space lives on its machine" "box" "$(jq -r 'select(.[0] == "space.new") | .[index("--machine") + 1]' $STUB_LOG)"
check "up: a tab's folder, under the machine's home" "/home/u/agt/box-sysadm" \
  "$(jq -r 'select(.[0] == "space.new") | .[index("--folder") + 1]' $STUB_LOG)"
check "up: a tab without one starts in the space's folder" "/home/u/agt" \
  "$(jq -r 'select(.[0] == "tab.new") | .[index("--folder") + 1]' $STUB_LOG)"
check "up: roles_cmd \"\" in a spaces/ file means no role tabs" "box-sysadm term" \
  "$($HRDRCFG show me@box | awk '$1 == "tab" {printf "%s%s", sep, $2; sep = " "}')"
check "ls: lists spaces/ files beside projects" "closed me@box" "$($HRDRCFG ls | awk '$2 == "me@box" {print $1, $2}')"

# discover on a project: an extra tab open, a configured one closed.
cat >$PROJ/.hrdrcfg/$USER.hrdrcfg <<'EOF'
tabs:
  - sh
  - name: outs
    run: intent expl outs
EOF
mkdir -p $PROJ/sub
jq -n '{spaces: [{id: "sp-demo", name: "devel/demo", tabs: [
  {name: "vc", terminals: [{terminal: "t1", app: null}]},
  {name: "review", terminals: [{terminal: "t2", app: "claude-code"}]},
  {name: "sh", terminals: [{terminal: "t3", app: null}]}]}]}' >$STUB_LS
jq -n --arg r $PROJ --arg s $PROJ/sub '{t1: $r, t2: $s, t3: $r}' >$STUB_CWDS
before=$(<$PROJ/.hrdrcfg/$USER.hrdrcfg)
(cd $PROJ && $HRDRCFG discover --dry-run >$TMP/dry.out)
check "discover --dry-run writes nothing" "$before" "$(<$PROJ/.hrdrcfg/$USER.hrdrcfg)"
check "discover --dry-run reports the extra tab" "1" "$(grep -c '+ tab review' $TMP/dry.out)"
check "discover --dry-run reports the closed tab" "1" "$(grep -c -- '- tab outs' $TMP/dry.out)"
check "discover: a closed role is reported, not written" "1" "$(grep -c 'role dc not open' $TMP/dry.out)"
(cd $PROJ && $HRDRCFG discover --yes >/dev/null)
check "discover --yes: tabs follow Herdr, roles left out" "review sh" "$(yq -r '.tabs[].name' $PROJ/.hrdrcfg/$USER.hrdrcfg | paste -sd ' ' -)"
check "discover: a new tab keeps its own folder" "$PROJ/sub" "$(yq -r '.tabs[] | select(.name == "review") | .folder' $PROJ/.hrdrcfg/$USER.hrdrcfg)"
check "discover: it wrote the user's file, not dft" "space: devel/demo" "$(grep -v '^#' $PROJ/.hrdrcfg/dft.hrdrcfg)"

# discover --all: an open space no config describes gets a spaces/ file.
jq -n '{spaces: [{id: "sp-l", name: "loose", machine: null, tabs: [
  {name: "agent", terminals: [{terminal: "t8", app: "claude-code"}]},
  {name: "term", terminals: [{terminal: "t9", app: null}]}]}]}' >$STUB_LS
jq -n --arg a $HOME/agt/agent --arg t $HOME '{t8: $a, t9: $t}' >$STUB_CWDS
$HRDRCFG discover --all --yes >/dev/null
f=$HRDRCFG_SPACES/loose.hrdrcfg
check "discover --all: writes a spaces/ file for an unconfigured space" "loose" "$(yq -r .space $f 2>/dev/null)"
check "discover --all: its folder is the first tab's, as ~" "~/agt/agent" "$(yq -r .folder $f)"
check "discover --all: tabs in Herdr's order, folders where they differ" "agent: term:~" \
  "$(yq -r '.tabs[] | .name + ":" + (.folder // "")' $f | paste -sd ' ' -)"
no_spaces; reset
$HRDRCFG up loose >/dev/null
check "up: a discovered space builds again" "agent term" "$(jq -r 'select(.[0] | test("space.new|tab.new")) | if .[0] == "space.new" then .[index("--tab") + 1] else .[index("--name") + 1] end' $STUB_LOG | paste -sd ' ' -)"

# --- 0.3.0: order -----------------------------------------------------------------

# Three ordered spaces (one on another machine), and two without an order.
for s in first:1 second:2 third:3; do
  print -r -- "space: ${s%%:*}"$'\n'"order: ${s##*:}"$'\n'"tabs: [sh]" >$HRDRCFG_SPACES/${s%%:*}.hrdrcfg
done
print -r -- $'space: far\nmachine: box\norder: 1\ntabs: [sh]' >$HRDRCFG_SPACES/far.hrdrcfg
jq -n '{spaces: [
  {id: "sp-l", name: "loose", machine: null, tabs: []},
  {id: "sp-3", name: "third", machine: null, tabs: []},
  {id: "sp-d", name: "devel/demo", machine: null, tabs: []},
  {id: "sp-1", name: "first", machine: null, tabs: []},
  {id: "sp-2", name: "second", machine: null, tabs: []},
  {id: "box/sp-b", name: "me@box", machine: "box", tabs: []},
  {id: "box/sp-f", name: "far", machine: "box", tabs: []}]}' >$STUB_LS
reset
$HRDRCFG sort >/dev/null
# Replay the moves on the list as Herdr would (index counts from 1), each inside its machine's block.
got=$(jq -rn --slurpfile ls $STUB_LS --slurpfile moves $STUB_LOG '
  def move($id; $i): (map(select(. != $id))) as $r | $r[:$i - 1] + [$id] + $r[$i - 1:];
  $ls[0].spaces | group_by(.machine // "") | map(map(.id)) as $blocks |
  reduce ($moves[] | {id: .[index("--id") + 1], i: (.[index("--index") + 1] | tonumber)}) as $m
    ($blocks; map(if index($m.id) then move($m.id; $m.i) else . end)) | flatten | join(" ")')
check "sort: ordered spaces first, lowest first, the rest kept in Herdr's order" \
  "sp-1 sp-2 sp-3 sp-l sp-d box/sp-f box/sp-b" "$got"
reset
jq -n '{spaces: [{id: "sp-1", name: "first", machine: null, tabs: []}, {id: "sp-l", name: "loose", machine: null, tabs: []}]}' >$STUB_LS
$HRDRCFG sort >/dev/null
check "sort: an ordered list is left alone" "" "$(calls)"
print -r -- $'space: bad\norder: soon\ntabs: [sh]' >$HRDRCFG_SPACES/bad.hrdrcfg
check "sort: an order that is not a number is refused" "hrdrcfg: bad: order is soon, not a whole number" "$($HRDRCFG sort 2>&1)"
rm $HRDRCFG_SPACES/bad.hrdrcfg

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))

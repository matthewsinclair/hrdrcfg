# hrdrcfg

Open a [Herdr](https://herdr.dev) space from its own config: one command builds the space and its tabs, another closes it. Keep only the spaces you are working in open, instead of every project at once. And when you change a space by hand in Herdr, `discover` offers to write the change back.

```
$ cd ~/Devel/prj/Molt
$ hrdrcfg up            # build the space, or show it if it is already open
$ hrdrcfg down          # close it (asks first if an agent is running in it)
$ hrdrcfg show          # print the space and tabs it would build; change nothing
$ hrdrcfg ls            # every configured space, open or closed
$ hrdrcfg discover      # compare what Herdr runs with the config; offer each change
$ hrdrcfg init          # write a starter .hrdrcfg/dft.hrdrcfg
$ hrdrcfg up matts@box  # a space that is not a project, by name
```

## Two kinds of space

- **A project** holds its config in `.hrdrcfg/` at its root, committed with it. `up`, `down`, `show` and `discover` find it the way git finds a repository: the nearest folder at or above the current one that holds `.hrdrcfg/`. Or name the folder.
- **A space that is not a project** (a machine's agents, say) is one file in `~/.config/hrdrcfg/spaces/`, named for the space (`matts@box.hrdrcfg`; a `/` in the name becomes `_`). Name it to `up`, `down`, `show` or `discover`.

## Config

YAML layers, each laid over the one before (maps merge, lists are replaced whole):

| File | Whose | Holds |
|---|---|---|
| `~/.config/hrdrcfg/config.yaml` | the user's | defaults for every space, and `roots` |
| `<project>/.hrdrcfg/dft.hrdrcfg` | the project's, committed | the project's own settings |
| `<project>/.hrdrcfg/<user>.hrdrcfg` | one user's, committed | that user's overrides (`<user>` is `$USER`) |
| `~/.config/hrdrcfg/spaces/<name>.hrdrcfg` | the user's | a space that is not a project, in place of the two above |

Keys:

- `space`: the Herdr space name. Default: the project folder's name, lowercased.
- `machine`: the Herdr machine the space lives on (`hc machine ls`). Default: this one.
- `folder`: a `spaces/` file's root folder. Default: `~`. A project's root is its own folder.
- `roles_cmd`: a shell command, run in the root, that prints one role per line. Each role becomes a tab of that name, before `tabs`. `""` for none. hrdrcfg does not know or care where roles come from.
- `roles_order`: roles to put first, in this order; any others follow in the order printed.
- `tabs`: tabs after the roles. Each is a name (a shell in the root), or `{name, run, folder}`: `run` is a command line (split as the shell splits words; no pipes) or a list of words; `folder` is relative to the root, absolute, or `~/...`.
- `roots`: folders `ls` and `discover --all` search for projects: each folder itself, and its children, that hold `.hrdrcfg/`.

On another machine, a folder is the same path under that machine's home, so it must sit under `$HOME` here.

## discover

`hrdrcfg discover` compares an open space with its config and offers each difference, one question at a time:

- `+` a tab open in Herdr and in no config: add it, after the open tab before it, with its folder if that is not the root.
- `-` a configured tab not open: remove it from the config (default: keep).
- `~` the configured tabs in another order than Herdr's: take Herdr's.
- `.` a role tab not open: reported only. Role tabs come from `roles_cmd` and are never written.

It writes `tabs` whole, because lists replace rather than merge: to `.hrdrcfg/<user>.hrdrcfg` in a project (`--to dft` for the project's defaults), or to the `spaces/` file. `--dry-run` only reports; `--yes` accepts everything; with no terminal to ask on, it declines.

`hrdrcfg discover --all` does this for every open space, and offers a new `spaces/` file for an open space no config describes: its folder is its first tab's, its tabs are Herdr's, each with its folder where that differs. A tab's folder is where its shell is now, which for an agent started from somewhere else may not be where it belongs: read what it proposes.

## Example

`~/.config/hrdrcfg/config.yaml`, with roles from [Intent](https://github.com/matthewsinclair/intent)'s whiteboard:

```yaml
roles_cmd: intent wb status --json 2>/dev/null | jq -r '.[] | select(.moniker != "hv") | .moniker'
roles_order: [vc, dc, ic, cc, ac]
tabs:
  - sh
  - name: outs
    run: intent expl outs
roots: [~/Devel/prj, ~/Devel/client/zeop, ~/Devel/client/zeop/initiatives]
```

`~/Devel/prj/Molt/.hrdrcfg/dft.hrdrcfg`:

```yaml
space: devel/molt
```

`hrdrcfg up` in Molt then opens `devel/molt` with tabs `vc dc cc ac sh outs`, each a shell in the Molt root, and `outs` running `intent expl outs`.

`~/.config/hrdrcfg/spaces/matts@box.hrdrcfg`, a machine's agents:

```yaml
space: matts@box
machine: box
folder: ~/Devel/agt
roles_cmd: ""
tabs:
  - name: box-sysadm
    folder: box-sysadm
  - term
```

## Requirements

zsh, [jq](https://jqlang.org), [yq](https://github.com/mikefarah/yq) v4, and Herdr's `herdr-app` and `hc` on `PATH`. `HRDRCFG_HERDR`, `HRDRCFG_HC`, `HRDRCFG_CONFIG` and `HRDRCFG_SPACES` name others.

## Tests

```
$ zsh test/run.zsh
```

They run hrdrcfg against stand-ins for `herdr-app` and `hc`, and never touch a real window.

## Licence

MIT. See `LICENSE`.

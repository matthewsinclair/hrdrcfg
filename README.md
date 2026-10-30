# hrdrcfg

Open a project's [Herdr](https://herdr.dev) space from the project's own config: one command builds the space and its tabs, another closes it. Keep only the projects you are working on open, instead of every project at once.

```
$ cd ~/Devel/prj/Molt
$ hrdrcfg up       # build the space, or show it if it is already open
$ hrdrcfg down     # close it (asks first if an agent is running in it)
$ hrdrcfg show     # print the space and tabs it would build; change nothing
$ hrdrcfg ls       # projects under your roots, open or closed
$ hrdrcfg init     # write a starter .hrdrcfg/dft.hrdrcfg
```

## Config

Three YAML layers, each laid over the one before (maps merge, lists are replaced whole):

| File | Whose | Holds |
|---|---|---|
| `~/.config/hrdrcfg/config.yaml` | the user's | defaults for every project, and `roots` for `ls` |
| `<project>/.hrdrcfg/dft.hrdrcfg` | the project's, committed | the project's own settings |
| `<project>/.hrdrcfg/<user>.hrdrcfg` | one user's, committed | that user's overrides (`<user>` is `$USER`) |

Keys:

- `space`: the Herdr space name. Default: the project folder's name, lowercased.
- `machine`: the Herdr machine the space lives on (`hc machine ls`). Default: this one. The project must sit under `$HOME`; its folder there is the same path under that machine's home.
- `roles_cmd`: a shell command, run in the project root, that prints one role per line. Each role becomes a tab of that name, before `tabs`. hrdrcfg does not know or care where roles come from.
- `roles_order`: roles to put first, in this order; any others follow in the order printed.
- `tabs`: tabs after the roles. Each is a name (a shell), or `{name, run}`, where `run` is a command line (split as the shell splits words; no pipes) or a list of words.
- `roots`: folders `ls` searches: each folder itself, and its children, that hold `.hrdrcfg/`.

`up` and `show` find the project the way git finds a repository: the nearest folder at or above the current one that holds `.hrdrcfg/`.

## Example

`~/.config/hrdrcfg/config.yaml`, with roles from [Intent](https://github.com/matthewsinclair/intent)'s whiteboard:

```yaml
roles_cmd: intent wb status --json | jq -r '.[] | select(.moniker != "hv") | .moniker'
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

## Requirements

zsh, [jq](https://jqlang.org), [yq](https://github.com/mikefarah/yq) v4, and Herdr's `herdr-app` (and `hc`, for a space on another machine) on `PATH`. `HRDRCFG_HERDR`, `HRDRCFG_HC` and `HRDRCFG_CONFIG` name others.

## Tests

```
$ zsh test/run.zsh
```

They run hrdrcfg against a stand-in `herdr-app` and never touch a real window.

## Licence

MIT. See `LICENSE`.

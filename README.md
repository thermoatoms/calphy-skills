# calphy-skills

Agent skills for [calphy](https://calphy.org), the free-energy calculation code
built on LAMMPS. Each skill is a `SKILL.md` folder in the
[Agent Skills](https://agentskills.io) format and works with OpenAI Codex and Claude
Code. The skills help an AI agent install calphy, write a valid input, pick the
right calculation, run it on a laptop or cluster, read the results, and judge
whether they can be trusted.

Written against **calphy 2.1.2**. The keyword table and error messages were taken from
the calphy source and the test inputs were run against a real LAMMPS binary.

## Skills

| skill | use it for |
|---|---|
| `calphy-install` | conda/pip/source install, which LAMMPS packages are needed, `lmp` resolution, preflight, library backend, smoke test |
| `calphy-choose-mode` | mapping a physics question to `fe`, `ts`, `tscale`, `pscale`, `alchemy`, `composition_scaling`, or `melting_temperature`, and when calphy is not applicable |
| `calphy-input-file` | the v2 `calculations:` layout, a validated template, recipes by intent, full keyword reference with defaults and validation errors |
| `calphy-free-energy` | `mode: fe` and `fe-qtb`: workflow, settings, report fields, trust checklist |
| `calphy-temperature-sweep` | `ts`, `tscale`, `pscale`: windows, phase-transition detection, sweep files, transition temperatures, entropy and cp |
| `calphy-melting-temperature` | automated and manual melting points, bracket choice, what makes a Tm unreliable |
| `calphy-alchemy` | potential-to-potential switching, upsampling, composition scaling and its missing mixing entropy |
| `calphy-run` | `calphy` vs `calphy_kernel`, local/SLURM/SGE, MPI cores, monitoring, rerunning, library backend, Python API |
| `calphy-analyse-results` | `report.yaml`, sweep files, `gather_results`, `find_transition_temperature`, combining runs, phase-diagram workflow |
| `calphy-troubleshoot` | error text to cause to fix, hangs, and how to tell a finished-but-wrong run |

## Install

### Claude Code plugin

```
/plugin marketplace add thermoatoms/calphy-skills
/plugin install calphy@calphy-skills
```

Skills are then available as `/calphy:calphy-install`, `/calphy:calphy-input-file`, and
so on, and are also picked up automatically when a request matches a description.

### OpenAI Codex plugin

In Codex CLI, enter `/plugins`, choose **Add Marketplace**, and add
`https://github.com/thermoatoms/calphy-skills`. Install **calphy**, then start a new
Codex session. The same marketplace is compatible with both Claude Code and Codex.
The equivalent terminal commands are:

```bash
codex plugin marketplace add thermoatoms/calphy-skills
codex plugin add calphy@calphy-skills
```

Installed skills can be selected with `/skills` or mentioned as `$calphy-install`,
`$calphy-input-file`, and so on. Codex can also select them automatically when a
request matches a skill description. Plugins are available in Codex CLI and the
ChatGPT desktop app; for the Codex IDE extension, use standalone skill folders.

### Standalone skill folders

Copy any `skills/<name>/` directory into the location used by your agent:

| host | all projects | one project |
|---|---|---|
| OpenAI Codex | `~/.agents/skills/` | `.agents/skills/` |
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |

Codex also supports installing skills from a GitHub repository with
`$skill-installer`.

## Layout

```
.codex-plugin/plugin.json         Codex compatibility manifest
.claude-plugin/plugin.json        plugin manifest
.claude-plugin/marketplace.json   marketplace for Claude Code and Codex
plugin.json                       portable Agent Plugins manifest
skills/<name>/SKILL.md            one skill per folder
skills/calphy-input-file/references/keywords.md   full keyword table
skills/calphy-install/scripts/    setup checker and smoke-test input
```

## Keeping the skills current

The skills state calphy behaviour precisely, so they go stale when calphy changes.
On each calphy release:

1. Diff `calphy/input.py` against `skills/calphy-input-file/references/keywords.md`.
2. Run `skills/calphy-install/scripts/smoke_input.yaml` and confirm the free energy.
3. Grep the calphy source for the error strings quoted in `calphy-troubleshoot`.
4. Bump `version` in `plugin.json`, `.codex-plugin/plugin.json`, and the Claude
   plugin and marketplace manifests.

Validate every skill with Codex's `quick_validate.py` (from
`skills/.system/skill-creator/scripts/` in the openai/skills repository), validate
the Codex plugin manifest, and run `claude plugin validate .` before release.

## License

MIT. calphy itself is distributed under the Academic Software Licence; see the
calphy repository.

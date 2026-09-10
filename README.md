# calphy-skills

Agent skills for [calphy](https://calphy.org), the free-energy calculation code
built on LAMMPS. Each skill is a `SKILL.md` folder in the
[Agent Skills](https://agentskills.io) format, written for an AI agent that has to
install calphy, write a valid input, pick the right calculation, run it on a laptop
or cluster, read the results, and judge whether they can be trusted.

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

### Plain skill folders

Copy any `skills/<name>/` directory into `~/.claude/skills/` (all projects) or
`.claude/skills/` in a project. Other agents that read the Agent Skills format can
point at the `skills/` directory directly.

## Layout

```
.claude-plugin/plugin.json        plugin manifest
.claude-plugin/marketplace.json   lets `plugin marketplace add` find the plugin
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
4. Bump `version` in both manifests.

`claude plugin validate .` checks the manifests.

## License

MIT. calphy itself is distributed under the Academic Software Licence; see the
calphy repository.

---
name: calphy-input-file
description: Write or fix a calphy `input.yaml` that passes calphy 2.x validation. Use when creating an input file for any calphy calculation, converting a v1 (top-level keys) file to the v2 `calculations:` list, or resolving a pydantic validation error such as "unknown key", "Element ordering mismatch", "legacy calphy input format", or "Input should be a valid string".
---

# Write a calphy input file

## Layout rules that break most files

1. **One top-level key**: `calculations:`, a YAML list. `element`, `mass`, `pair_style`,
   `md`, `queue`, everything, goes inside each list entry. A top-level `element:` is
   the v1 format and is rejected.
2. **One structure per entry.** `lattice` and `reference_phase` are strings, not lists.
   `lattice: [fcc, fcc]` fails with `Input should be a valid string`. Solid and liquid
   of the same system are two entries.
3. **Keys are checked strictly** and the error names the closest match and the block
   the key belongs in. `npt`, `equilibration_control`, `melting_cycle` are
   calculation-level. `timestep`, `cmdargs`, `init_commands`, `seed` live under `md:`.
4. **Element order is the LAMMPS type order.** `element`, `mass`, and the element list
   at the end of `pair_coeff` must agree exactly. Multi-element systems must use a
   LAMMPS data file as `lattice`; built-in lattices are single element.
5. **Absolute paths for every potential file.** calphy runs LAMMPS inside a
   subfolder. It rewrites the first path in `pair_coeff` to absolute, but MEAM
   parameter files, `mlip.ini` in `pair_style`, and similar secondary files are not
   rewritten. Write them absolute yourself.
6. `temperature` is one value for `fe`, `pscale`, `alchemy`, `composition_scaling`;
   two values `[T0, Tf]` for `ts` and `tscale`; optional for `melting_temperature`.
   `pressure` is in bar; a two-value list is only valid for `pscale`; `None` means
   fixed box.
7. Each entry becomes one job. `calphy -i input.yaml` submits all, `calphy_kernel -i input.yaml -k N` runs entry N.

## Minimal template

```yaml
calculations:
- element: Cu
  mass: 63.546
  mode: fe                     # fe | fe-qtb | ts | tscale | pscale | alchemy | composition_scaling | melting_temperature
  lattice: fcc                 # bcc fcc hcp diamond sc | /abs/path/structure.data | mp-30
  lattice_constant: 3.615      # only for built-in lattices
  repeat: [5, 5, 5]            # only for built-in lattices; ignored for data files
  reference_phase: solid       # solid | liquid
  temperature: 500             # [T0, Tf] for ts/tscale
  pressure: 0                  # bar
  pair_style: eam/alloy
  pair_coeff: '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000
  n_iterations: 3              # >1 to get an error bar
  queue:
    scheduler: local
    cores: 4
```

Quote `pair_coeff` strings: `* *` is otherwise a YAML alias.

## Recipes by intent

| intent | set |
|---|---|
| Solid free energy at (T, P) | `mode: fe`, `reference_phase: solid` |
| Liquid free energy | `mode: fe`, `reference_phase: liquid`, start from a crystal; add `temperature_high` if it does not melt |
| Free energy vs T over a range | `mode: ts`, `temperature: [T0, Tf]`. Start at the low end. |
| Same but the potential cannot use `hybrid/scaled` (Kokkos, some ML styles) | `mode: tscale` |
| Free energy vs P | `mode: pscale`, `pressure: [P0, Pf]` |
| Melting point, automated | `mode: melting_temperature`, no `lattice`/`temperature` needed for one element |
| Melting point, manual | two `ts` entries, solid and liquid, same `temperature` window |
| Switch potential A to B | `mode: alchemy`, two `pair_style` and two `pair_coeff` entries |
| Change composition | `mode: composition_scaling` with `composition_scaling.output_chemical_composition`, every `pair_coeff` starting `* *` |
| Multi-term potential (e.g. `coul/long` + `eam/alloy`) | `pair_mode: overlay`, component styles listed in `pair_style` |
| Nuclear quantum effects below ~half the Debye T | `mode: fe-qtb` (solid only), tune `quantum_thermal_bath.f_max` |
| Fixed box, no barostat | `pressure: None` (fe and alchemy only) |
| Triclinic cell | data file as `lattice`, `pressure_coupling: tri` |
| GPU / Kokkos | `md.cmdargs: "-k on g 1 -sf kk -pk kokkos newton on neigh half"` (see troubleshooting: `hybrid/scaled` has no Kokkos variant) |
| Skip NPT pressure convergence trouble | pre-equilibrate in LAMMPS, pass the data file, or give a converged `lattice_constant` |
| Pre-melted liquid structure | `melting_cycle: False` |

## Sanity checks before running

Validate without running LAMMPS:

```bash
python -c "from calphy.input import read_inputfile; c = read_inputfile('input.yaml'); print(len(c), 'calculation(s)'); [print(x.mode, x.lattice, x.reference_phase, x._temperature, x._pressure) for x in c]"
```

Validation builds the structure and writes `<mode>-<lattice>-...<k>.data` into the
current directory as a side effect; delete it or run the check in a scratch folder.

Also check that:

- every potential file path exists (`ls` each one);
- `lmp` resolves (`which lmp` or `$CALPHY_LAMMPS_EXECUTABLE`), see the calphy-install skill;
- the output folder `<mode>-<lattice>-<phase>-<T>-<P>` does not already exist, or set `folder_prefix`;
- for liquids the temperature is above the melting point of the potential, and
  `temperature_high` (default 2T) will actually melt it;
- `n_iterations` is at least 3 if an error bar is needed.

## Cost and size guidance

- Aim for 500 to 4000 atoms. `repeat: [5,5,5]` fcc is 500 atoms and fine for tests;
  publication-quality Tm work in the examples uses `[10,10,10]` (4000 atoms).
- `n_switching_steps: 25000` with `n_equilibration_steps: 10000` is the documented
  example scale and gives results within ~50 K on melting points. `50000` and above
  for production. Check convergence by plotting the free energy against
  `n_switching_steps`; it should flatten.
- Runtime is roughly proportional to
  `n_iterations * (n_equilibration_steps + 2 * n_switching_steps) * natoms`, plus the
  pressure-convergence cycles (`md.n_small_steps` each, up to `md.n_cycles`).

## Full keyword reference

Read [references/keywords.md](references/keywords.md) for every key, default, allowed
value, and the validation errors calphy raises. It is derived from `calphy/input.py`
in calphy 2.1.2; if calphy has moved on, trust the installed `calphy/input.py`.

# calphy 2.1 input keyword reference

Source of truth: `calphy/input.py` (pydantic models) and `docs/source/inputfile.md`
in the calphy repository. Verified against calphy 2.1.2. When this file and a newer
calphy disagree, trust `calphy/input.py`.

## File layout rules (v2)

- The file has exactly one top-level key: `calculations:`, a YAML list.
- **Everything else goes inside each list entry**, including `element`, `mass`,
  `pair_style`, `pair_coeff`, `md`, `queue`, `tolerance`. A top-level `element:` key
  is the legacy v1 format and is rejected with
  `uses the legacy calphy input format`. Automatic conversion was removed in v2.
- Keys are validated strictly. An unknown key anywhere raises at startup and the error
  names the closest match and, if the key belongs in another block, where it belongs.
- Each list entry is one job. `calphy -i input.yaml` submits entry `k` as kernel `k`;
  `calphy_kernel -i input.yaml -k <k>` runs entry `k` directly.
- `script_mode` was removed in v2 and raises a validation error if present.

## Calculation-level keys

| key | type | default | notes |
|---|---|---|---|
| `element` | str or list | required | Order defines LAMMPS atom types: `element[0]` is type 1. |
| `mass` | float or list | required, same length as `element` | Same order as `element`. |
| `mode` | str | required | `fe`, `fe-qtb`, `ts`, `tscale`, `pscale`, `alchemy`, `composition_scaling`, `melting_temperature`. |
| `lattice` | str | `""` | `bcc`, `fcc`, `hcp`, `diamond`, `sc` (single element only, built with pyscal3), a LAMMPS data file path, or a Materials Project id like `mp-30`. Empty: calphy looks up a default structure for the element. |
| `lattice_constant` | float | experimental value | Only for built-in lattices. Required if the element has no tabulated value. |
| `repeat` | list of 3 ints | `[1,1,1]` | Only for built-in lattices. If `lattice` is empty and `repeat` is left at default, calphy uses `[5,5,5]`. |
| `reference_phase` | str | `""` | `solid` (Einstein crystal reference) or `liquid` (Uhlenbeck-Ford reference). |
| `temperature` | float or list | required except `melting_temperature` | Single value for `fe`; two values `[T0, Tf]` for `ts`/`tscale`; unused for `pscale` beyond the single value. |
| `temperature_high` | float | `2 * T` (T = highest temperature) | Overheat temperature used to melt the structure when `reference_phase: liquid`. |
| `pressure` | None, float, or list | `0` | Bars. Shape decides the barostat, see the pressure table below. `None` fixes the box (NVT). |
| `pressure_coupling` | str | inferred | `iso`, `aniso`, `tri`. Overrides the shape-based inference. `tri` needs a triclinic data file. |
| `npt` | bool | `True` | `ts`: sweep in NPT (True) or NVT (False). `alchemy`: False means NVT at the volume of the first potential. |
| `pair_style` | str or list | required | One entry normally. Two entries for `alchemy` (from, to). Component styles for `pair_mode: overlay`. Options go with the style, e.g. `"coul/long 11.0"`. |
| `pair_coeff` | str or list | required | Same length as `pair_style`. Element list at the end must match `element` in the same order. Paths are made absolute unless `fix_potential_path: False`. |
| `pair_mode` | str | None | `overlay` combines several component styles into one physical potential via `hybrid/overlay`. Not allowed with `alchemy`. |
| `potential_file` | str | None | Deprecated. Only works with `mode: fe`, `reference_phase: solid`. |
| `fix_potential_path` | bool | `True` | Expand `~`, `$VAR`, and make potential paths absolute. |
| `file_format` | str | `lammps-data` | Only supported value. |
| `n_equilibration_steps` | int | `25000` | Full length used wherever the system reaches a new state. Re-thermalisation blocks are shortened to ten damping times, capped at this value. |
| `n_switching_steps` | int or `[int, int]` | `50000` | Switching (Frenkel-Ladd or alchemical) length. As a pair: first value for `fe`-type switching, second for the reversible-scaling sweep. |
| `n_iterations` | int | `1` | Independent forward+backward cycles. Needed for an error bar: `error` is the standard error of the mean over iterations. |
| `lambda_schedule` | str | `linear` | `ts` only. `uniform_temperature` spreads samples evenly in T. Does not change the result, only the error profile. |
| `n_print_steps` | int | `0` | Dump interval for trajectories during sweeps. 0 = never. |
| `n_print_steps_equilibration` | int | `0` | Dump interval during equilibration. Undocumented in the manual; present in `input.py`. |
| `spring_constants` | list of floats | None | One per element. Skips the automatic MSD fit for the Einstein crystal. |
| `equilibration_control` | str | None | `berendsen` or `nose-hoover` for the equilibration stage. Default: Berendsen for solid, Nose-Hoover for liquid. Ignored in `fe-qtb`. |
| `melting_cycle` | bool | `True` in `input.py` (manual says False) | Liquid only. Whether to overheat and quench the input structure. |
| `folder_prefix` | str | None | Prepended to the output folder name. Use it to avoid `folder already exists` when re-running the same state. |
| `execution_mode` | str | `executable` | `executable` (runs `lmp` as a subprocess) or `library` (pylammpsmpi, needs `pip install calphy[library]` and the LAMMPS python module). |
| `lammps_executable` | str | None | Path to `lmp`. Resolution: this key, then `$CALPHY_LAMMPS_EXECUTABLE`, then `lmp` on PATH. |
| `mpi_executable` | str | None | Used when `queue.cores > 1`. Resolution: this key, then `$CALPHY_MPI_EXECUTABLE`, then `mpirun` on PATH. |
| `phase_name` | str | `""` | Label used by the phase-diagram post-processing to group rows. |
| `reference_composition` | float | `0.0` | Set by the phase-diagram driver; rarely set by hand. |
| `alchemy_coupling` | bool | `False` | Internal flag; leave unset. |

### `pressure` shapes

| input | barostat | box | allowed modes |
|---|---|---|---|
| `None` | none | fixed (NVT) | `fe`, `alchemy` |
| `100` or `[100]` | `iso` | relaxed | all except `pscale` |
| `[100, 200]` | `iso` | relaxed | `pscale` only (start, stop) |
| `[100,100,100]` or `[[100,100,100]]` | `aniso` | relaxed, components must be equal | all except `pscale` |
| `[[100,100,100],[200,200,200]]` | `aniso` | relaxed | `pscale` only |

## `md` block

| key | default | notes |
|---|---|---|
| `timestep` | `0.001` | ps |
| `thermostat_damping` | `0.1` | ps, used in the switching stage |
| `barostat_damping` | `0.1` | ps |
| `n_small_steps` | `10000` | Steps per convergence cycle (pressure and spring constant). |
| `n_every_steps` | `10` | `fix ave/time` Nevery |
| `n_repeat_steps` | `10` | `fix ave/time` Nrepeat |
| `n_cycles` | `100` | Max convergence cycles before an error. |
| `cmdargs` | `""` | Extra `lmp` argv, e.g. `"-k on g 1 -sf kk -pk kokkos newton on neigh half"`. Do not pass `-in`, `-log`, `-screen`. |
| `init_commands` | `[]` | LAMMPS commands added or overriding at init, e.g. `atom_style charge`. Highest priority. |
| `seed` | None | Master seed. If unset a fresh one is drawn and backfilled into the `input_file.yaml` copy in the run folder. |

## `queue` block

| key | default | notes |
|---|---|---|
| `scheduler` | `local` | `local`, `slurm`, `sge` |
| `cores` | `1` | MPI ranks. `>1` uses `mpirun` (or `mpi_executable`). |
| `jobname` | `calphy` | |
| `walltime` | `23:59:00` | string |
| `queuename` | `""` | partition |
| `memory` | `3GB` | Written as `#SBATCH --mem=` (whole job) despite the manual saying per core. |
| `commands` | `[]` | Lines copied verbatim into the submission script before the run, e.g. `conda activate calphy`. |
| `options` | `{}` | Extra scheduler options. |

## `tolerance` block

| key | default | notes |
|---|---|---|
| `lattice_constant` | `0.0002` | Å |
| `spring_constant` | `0.1` | |
| `pressure` | `10.0` | bar, on the average pressure during volume convergence |
| `solid_fraction` | `0.0` | Melt check for solids: raises `MeltedError` if the solid fraction drops below this. `0.0` disables it. Set `0.7` to enable. |
| `liquid_fraction` | `1.0` | Solidification check for liquids: raises `SolidifiedError` if the solid fraction exceeds this. `1.0` disables it. Set `0.05` to enable. |
| `dissipation` | `0.001` | eV/atom. Irreversible work above which the switching is questioned. `0` disables. Roughly 10 K on a melting point at 1 meV/atom. |

`mode: melting_temperature` re-enables the melt and solidification checks internally
because its bracket search depends on them.

## `melting_temperature` block

| key | default | notes |
|---|---|---|
| `guess` | None | Accepted by the validator but **not read** in 2.1.2; the bracket centres on `temperature` (default: mendeleev melting point of `element[0]`). |
| `step` | `200` | Bracket step in K, minimum 20. |
| `attempts` | `5` | Max bracket moves. |

## `composition_scaling` block

| key | default | notes |
|---|---|---|
| `output_chemical_composition` | `{}` | Element to atom count. Total must equal the input structure. Elements must exist in the potential. |
| `restrictions` | `[]` | `"A-B"` pairs that must not be transformed into each other. |

Every `pair_coeff` in this mode must start with `* *`.

## `phase_transition_detection` block (ts only)

| key | default | notes |
|---|---|---|
| `mode` | `none` | `none`, `adapt` (shrink the sweep to the clean range), `warn` (log only), `stop` (raise `PhaseTransitionError`). |
| `prescan_steps` | `20000` | Steps in the diagnostic ramp. |
| `onset_fraction` | `0.85` | Safety margin below the detected onset. |

## `uhlenbeck_ford_model` block (liquid reference)

| key | default | notes |
|---|---|---|
| `p` | `50.0` | Must be one of 1, 25, 50, 75, 100. Confinement strength in kB T. Too small loses light atoms (drift). |
| `sigma` | `1.5` | Å. Float for one-leg. Dict like `{H_H: 0.9, O_O: 2.8, H_O: 0.9}` for the two-leg path (molecular liquids). |
| `single_sigma` | None | Required with dict `sigma`. Small (~1.0 Å) single-component endpoint. |
| `single_p` | None | Falls back to `p`. |

## `monte_carlo` block (alchemy and composition_scaling)

| key | default |
|---|---|
| `n_steps` | `1` |
| `n_swaps` | `0` (disabled) |
| `forward_swap_types` | `[]` |
| `reverse_swap_types` | `[]` |
| `allow_all_swaps` | `True` |
| `use_custom_lammps` | `False` |

## `quantum_thermal_bath` block (`mode: fe-qtb`, solids only)

| key | default | notes |
|---|---|---|
| `thermostat_damping` | `0.1` | ps |
| `barostat_damping` | `0.1` | ps |
| `f_max` | `200.0` | THz. Must exceed the highest phonon frequency. Simple metals: 30 is enough. Hydrides: 100+. |
| `n_f` | `100` | frequency bins |

## `nose_hoover` and `berendsen` blocks

Equilibration-stage damping. `nose_hoover`: both dampings default `0.1`.
`berendsen`: both default `100.0`.

## `materials_project` block

| key | default | notes |
|---|---|---|
| `api_key` | `""` | Name of the env var holding the key, e.g. `MP_API_KEY`. Not the key itself. |
| `conventional` | `True` | |
| `target_natoms` | `1500` | Replicate until roughly this many atoms, unless `repeat` is set. |

## Validation errors you will see and what they mean

| message (abridged) | cause |
|---|---|
| `uses the legacy calphy input format` | `element:` at top level. Move everything under `calculations: - ...`. |
| `unknown top-level key(s)` | Only `calculations:` may be top level. |
| `mass and elements should have same length` | Lengths differ. |
| `Element ordering mismatch detected!` | `element`, `mass`, and the tail of `pair_coeff` are not in the same order. |
| `Element mismatch between 'element' and 'pair_coeff'!` | Different element sets. |
| `Cannot create lattice for more than one element` | Built-in lattice with several elements. Provide a data file. |
| `Please provide lattice_constant!` | Element has no tabulated lattice constant. |
| `All pressure terms must be equal` | Anisotropic pressure with unequal components. |
| `mode=fe-qtb is solids-only` | QTB with liquid reference. |
| `mode composition_scaling needs every pair_coeff to apply to all atom types` | `pair_coeff` not starting with `* *`. |
| `Input and output number of atoms are not conserved!` | `output_chemical_composition` total differs from the structure. |
| `pair_mode overlay is not supported for mode alchemy` | Use `composition_scaling` to change composition of an overlay potential. |

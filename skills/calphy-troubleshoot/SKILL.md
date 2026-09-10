---
name: calphy-troubleshoot
description: Diagnose a failed, hanging, or suspicious calphy run from its error text, calphy.log, LAMMPS segment logs, and report.yaml. Covers pair_style/pair_coeff and potential-path errors, MEAM and ML potentials, Kokkos and hybrid/scaled, pressure not converging, lost atoms, melted solids and frozen liquids, spring-constant nan/inf, high dissipation, missing temperature_sweep.dat, folder-exists errors, scheduler and MPI problems, and results that changed between calphy versions. Use whenever a calphy run did not finish or its number looks wrong.
---

# Troubleshoot calphy

## Where the error is

1. **Validation errors** (before any folder exists): printed to the terminal, or in
   `local.err` / `<identifier>.sub.slurm.err`. Fix the input (calphy-input-file).
2. **calphy errors** during the run: the Python traceback is in the same `.err` file
   and the last lines of `<folder>/calphy.log`.
3. **LAMMPS errors**: calphy raises `LammpsExecutionError: LAMMPS segment failed`
   naming the segment script and log. Open `<folder>/calphy.seg<k>.log`; the
   `ERROR:` line is at the end. Copy that line and match it below.
4. **Silent bad result**: run finished, number is off. Go to the last section.

## LAMMPS-side errors

| error text | cause | fix |
|---|---|---|
| `No MEAM parameter file in pair coefficients`, `Incorrect args for pair style meam coefficients`, `Cannot open ... potential file` | calphy makes only the **first** path in `pair_coeff` absolute; the second MEAM file, `mlip.ini`, and files inside `pair_style` options stay relative and break inside the run folder. | Write every potential path absolute. |
| `pair_coeff: element X not found`, `Unknown element`, `Incorrect args for pair coefficients` | Element list at the end of `pair_coeff` does not match the potential's elements or the `element` order. | Match `element`, `mass`, and `pair_coeff` tail in one order; use the symbols the potential file declares. |
| `Unrecognized pair style`, `Unrecognized fix style ti/spring`, `Unknown pair style ufm`, or the preflight message `The LAMMPS binary ... is missing styles this calculation needs` | `lmp` built without `EXTRA-FIX`, `EXTRA-PAIR`, `MC`, `QTB`, or the potential's package. | Rebuild or switch binary (calphy-install). |
| `Must use pair_style hybrid/scaled/kk with Kokkos` or `Unrecognized pair style hybrid/scaled/kk` | LAMMPS has no Kokkos version of `hybrid/scaled`, which liquid `fe` and `ts` use. | For solids use `mode: tscale` instead of `ts`, or drop `-sf kk`. Liquid free energies cannot run on Kokkos. |
| `Pair hybrid sub-style ... is not used` | Multi-term potential written as a `hybrid/overlay` `pair_style`. | Use `pair_mode: overlay` and list the component styles. |
| `Lost atoms` in a liquid run | Uhlenbeck-Ford reference cannot hold the atoms: molecular liquid (two length scales) or `uhlenbeck_ford_model.p` too small. | Two-leg UFM with per-pair `sigma` dict and `single_sigma`; keep `p: 50`. |
| `Lost atoms` in a solid run, `Divide by 0 in variable formula` | All atoms flew away: exploded structure, wrong units or masses, potential incompatible with the structure. | Check `conf.equilibration.data`; verify masses and `atom_style`; equilibrate in plain LAMMPS first and pass the data file. |
| `Style 'atomic' not supported or invalid number of fields` | Data file written with `atom_style charge` or another style. | calphy reads `atomic` data files only; convert, or add `atom_style` via `md.init_commands` for the run and write the file in `atomic` style. |
| `Illegal velocity create`, `Illegal fix langevin` with `0` as seed | Old bug (seed 0). | Update calphy; fixed. |
| `Cannot use fix press/berendsen with triclinic box` | Triclinic data file with default coupling. | `pressure_coupling: tri`, or `equilibration_control: nose-hoover`. |
| `newton off` required (nequip, some ML styles) | Style needs a different setting at init. | `md.init_commands: ["newton off"]`. |
| `Loading mliappy unified module failure` | Python-coupled ML-IAP not activated. | Use `execution_mode: library` with a LAMMPS build that provides `lammps.mliap`, or the `mliap` non-Python variant. |

## calphy-side errors

| error text | cause | fix |
|---|---|---|
| `Pressure did not converge after MD runs, maybe change lattice_constant and try?` | Small cell plus barostat noise; the average pressure did not reach `tolerance.pressure` (10 bar) within `md.n_cycles`. | Rerun (often enough). Give a converged `lattice_constant`, or a pre-equilibrated data file. Raise `tolerance.pressure` to 50 for tests. `equilibration_control: nose-hoover` if Berendsen defaults misbehave. `pressure: None` skips it entirely (fe/alchemy). |
| `System melted, increase size or reduce temp!` | Solid fraction dropped below `tolerance.solid_fraction` (only when enabled or in `melting_temperature` mode). | Lower T, bigger cell, check the structure is the stable one at T. Detection covers bcc/fcc/hcp/sc/diamond only; for other lattices set `tolerance.solid_fraction: 0` and check manually. |
| `System solidified, increase temperature` / `Liquid system did not melt, maybe try a higher thigh temperature.` | Liquid froze, or the melting cycle did not melt the crystal. | Raise `temperature_high` (default 2T), raise T, or supply a liquid data file with `melting_cycle: False`. |
| `Cannot fix lattice and melt structure (set to False) at the same time` | `pressure: None` with `melting_cycle: True` for a liquid. | Set `melting_cycle: False` and pass a liquid structure. |
| `At count N mean k is inf std is nan`, `MSD for element index N averaged to ~0` | Atoms did not move: an element in `element` has no atoms in the structure (composition 0), or wrong type mapping. | Remove unused elements or fix the data file types; set `spring_constants` manually as a last resort. |
| `Spring constant input length should be same as number of elements` | `spring_constants` list length mismatch. | One value per element. |
| `Simulation folder ... exists. Please remove and run again!` | Same state run twice, or a `melting_temperature` search revisiting a window. | Delete the folder or set `folder_prefix`. |
| `Mode should be either fe/ts/alchemy/melting_temperature/tscale/pscale/composition_scaling` | Typo in `mode` (e.g. an element symbol). | Fix `mode`. |
| `Unknown scheduler` | `queue.scheduler` not `local`, `slurm`, `sge`. | Fix or use a hand-written script. |
| `Could not resolve the LAMMPS executable` | No `lmp`. | `lammps_executable`, `$CALPHY_LAMMPS_EXECUTABLE`, or PATH. |
| `execution_mode 'library' requires pylammpsmpi` | Missing optional dependency. | `pip install calphy[library]`. |
| `Maximum number of tries reached`, `From calculation, Tm is not within range` | Melting bracket never contained Tm. | See calphy-melting-temperature. |
| `PhaseTransitionError: Pre-scan detected a phase transition` | `ts` window crosses melting or a solid-solid transition; mode `stop`. | Narrow the window or use `phase_transition_detection.mode: adapt`. |
| `alchemical switching needs pair_style and pair_coeff lists of equal, even length` | `alchemy` with one or three entries. | Exactly two of each. |
| `Composition scaling is untested for more than 2 elements!`, `A possible transformation could not be found` | Ternary system or `restrictions` too tight. | Keep to binaries; loosen restrictions. |
| `uses the legacy calphy input format`, `unknown top-level key(s)`, `Input should be a valid string` for `lattice` | v1-style file or list-valued `lattice`. | Rewrite as a `calculations:` list with one structure per entry (calphy-input-file). |
| `KeyError: 'calphy.range_scan'`-style import errors, missing `temperature_sweep.dat` after a `ts` run | Broken or partial install of an old release. | Upgrade calphy (`pip install -U calphy`). |

## Hangs

| symptom | cause | fix |
|---|---|---|
| Library mode, no output, no LAMMPS log | `lammps` Python module and `liblammps` versions differ. | `python -c "from lammps import lammps; lammps()"`; reinstall both from conda-forge together. |
| `mpiexec ... unrecognized argument oversubscribe`, `EOFError`, `BrokenPipeError` at startup | MPICH-built LAMMPS with pylammpsmpi (needs OpenMPI). | Install the `*openmpi*` LAMMPS build, or use the default executable mode. |
| Cluster job idle, `OPAL ERROR: Not initialized`, PMI errors | Site MPI launcher mismatch. | `CALPHY_MPI_EXECUTABLE=srun` (or the site launcher); test `mpirun -np 2 lmp -in in.test` outside calphy first. |
| Two local jobs each with `cores: N` crawl | Both pinned to the same cores. | Run sequentially or on separate nodes. |
| Orphaned `lmp`/`calphy_kernel` processes after a crash | Killed parent. | `pkill -f calphy_kernel; pkill lmp`. |

## The run finished but the number is wrong

Work down this list; stop at the first hit.

1. **Compare `average.vol_atom`** with the expected density. A solid several percent
   too large has melted; a liquid at crystal density has frozen. The default checks
   are off (`tolerance.solid_fraction: 0`, `liquid_fraction: 1`), so calphy will not
   have stopped. Rerun with the checks on or at a safer temperature.
2. **`average.spring_constant`** far from 1 to 10 eV/Å² (metals), `inf`, or
   bistable between reruns: the MSD fit failed or the solid is not vibrating about
   sites. Larger cell, longer `md.n_small_steps`, or explicit `spring_constants`.
3. **`results.dissipation`** does not shrink when `n_switching_steps` doubles: a
   structural change during the switch. Change the state point.
4. **`results.ts_dissipation`** above 1e-3 in a `ts` run: the sweep crossed a
   transition; the whole curve is contaminated. Narrow the window or use
   `phase_transition_detection`.
5. **`error` is 0.0**: single iteration; you have no idea of the precision. Run
   `n_iterations: 3`.
6. **Element order**: multi-element structures with `element`, `mass`, `pair_coeff`
   in different orders silently give the wrong potential per type in versions that
   did not check. Verify the LAMMPS `Masses` block in `calphy.seg0.lmp`.
7. **Different from a literature or older-calphy number**: check system size,
   `n_switching_steps`, `reference_phase`, pressure, and whether the old run was
   aborting on the melt check that is now disabled. Example inputs are deliberately
   small and reproduce melting points to about 50 K, not better. The equilibration
   rework between calphy 1.6 and 2.0 changes converged volumes by ~0.02 %, which is
   five orders of magnitude too small to move a melting point.
8. **Below the Debye temperature** with classical `fe`: zero-point effects are
   missing. Use `fe-qtb`.
9. **Molecular solids or liquids**: the Einstein-crystal reference does not handle
   molecules; the single-scale UFM does not handle two bond lengths. Only the two-leg
   UFM path is available, and only for liquids.

## Quick triage commands

```bash
tail -20 <folder>/calphy.log
grep -h ERROR <folder>/calphy.seg*.log | tail -3
grep -E "WARNING|dissipation|converge" <folder>/calphy.log | tail
python -c "import yaml; r=yaml.safe_load(open('<folder>/report.yaml')); print(r['average']); print(r['results'])"
```

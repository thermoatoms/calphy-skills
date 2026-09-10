---
name: calphy-free-energy
description: Run a calphy `mode: fe` (or `fe-qtb`) calculation to get the absolute Helmholtz or Gibbs free energy of a solid or liquid at one temperature and pressure, and judge whether the number can be trusted. Use for single-point free energies, Einstein-crystal or Uhlenbeck-Ford reference runs, liquid melting cycles, quantum-corrected solid free energies, and for validating report.yaml from an fe run.
---

# Single-point free energy (`mode: fe`)

## What the run does

1. **Equilibration and averaging.** Builds or reads the structure, runs NPT at (T, P)
   in cycles of `md.n_small_steps` until the average pressure is within
   `tolerance.pressure` (10 bar default) of the target, then fixes the box at the
   converged volume. Solid: fits the Einstein spring constant from the MSD. Liquid:
   first melts the input crystal at `temperature_high` (default 2T), quenches to T,
   then converges the volume.
2. **Switching**, `n_iterations` times: forward switch real potential to reference
   over `n_switching_steps`, then backward. Solid reference is an Einstein crystal
   (`fix ti/spring`); liquid reference is the Uhlenbeck-Ford fluid (`pair_style ufm`
   via `hybrid/scaled`).
3. **Integration.** `free_energy = reference_system + work + pv (+ com_correction for solids)`
   written to `report.yaml`. `error` is the standard error of the mean of the work
   over iterations, so it is `0.0` when `n_iterations: 1`.

The result is F at P = 0 and G at finite P.

## Input

Solid:

```yaml
calculations:
- element: Cu
  mass: 63.546
  lattice: fcc
  lattice_constant: 3.615
  repeat: [5, 5, 5]
  mode: fe
  reference_phase: solid
  temperature: 500
  pressure: 0
  pair_style: eam/alloy
  pair_coeff: '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000
  n_iterations: 3
  queue: {scheduler: local, cores: 4}
```

Liquid: same block with `reference_phase: liquid`, a temperature above the melting
point of the potential, and, if the crystal does not melt on its own,
`temperature_high` set well above Tm (for Cu at 1400 K, 2800 K default is fine).
If you already have an equilibrated liquid data file, pass it as `lattice` and set
`melting_cycle: False`.

Multi-element solid: `lattice: /abs/path/structure.data` with atoms on their sites,
`element`, `mass`, and the tail of `pair_coeff` in the same order.

Fixed box (F(V,T), no barostat): `pressure: None`. Then the pressure is not
converged; calphy reports the measured pressure and `pv` is 0.

## Choosing settings

| quantity | test | production | why |
|---|---|---|---|
| atoms | 500 | 1000 to 4000 | reference-system finite-size error, liquid needs more |
| `n_equilibration_steps` | 2500 | 10000 to 25000 | volume and spring-constant convergence |
| `n_switching_steps` | 5000 | 25000 to 100000 | dissipation falls with switching time; converge it |
| `n_iterations` | 1 | 3 to 5 | error bar |

Convergence test: run the same state with `n_switching_steps` at 10000, 25000,
50000 and plot `free_energy`; it should flatten to within your target precision.
Reference: Menon et al., Phys. Rev. Materials 5, 103801 (2021), Fig. 1b.

## Run it

```bash
calphy_kernel -i input.yaml -k 0        # one calculation, in the foreground
calphy -i input.yaml                    # submit every entry via queue.scheduler
```

Output folder: `fe-<lattice>-<phase>-<T>-<P>/`, e.g. `fe-fcc-solid-500-0/`.
See the calphy-run skill for clusters and monitoring.

## Read the result

```python
from calphy.postprocessing import read_report
r = read_report("fe-fcc-solid-500-0")
r["results"]["free_energy"], r["results"]["error"]     # eV/atom
r["average"]["vol_atom"], r["average"].get("spring_constant")
```

## Trust checklist

Work through every line. A run that finishes is not automatically a good run.

- **`results.dissipation`** is the mean irreversible work, reported with sign. Its
  magnitude falls with switching time: about 3 meV/atom at 5000 steps for Cu, below
  1 meV/atom at 25000 steps, ~1e-4 at 100000. A value that does not shrink when
  `n_switching_steps` is doubled points to a structural change during the switch.
  (`tolerance.dissipation` is only enforced automatically on `ts` sweeps.)
- **Solid stayed solid.** By default the melt check is OFF (`tolerance.solid_fraction: 0`).
  calphy logs `Melt detection is DISABLED`. Either set `tolerance.solid_fraction: 0.7`
  before running (only works for bcc/fcc/hcp/sc/diamond) or inspect
  `conf.equilibration.data` and `traj.equilibration_stage*.dat` afterwards. A melted
  "solid" typically shows a spring constant far below the expected value and a
  `vol_atom` jump of several percent.
- **Liquid stayed liquid.** Likewise `tolerance.liquid_fraction: 0.05` enables the
  check. Symptoms of a frozen liquid: `density` matches the crystal, `msd.dat` flat.
- **Spring constant is sane.** `average.spring_constant` should be of order
  1 to 10 eV/Å² for metals; `inf` or `nan` means the MSD averaged to zero
  (structure did not vibrate: wrong species mapping, or a multi-element potential used
  with a single-element structure). Warning text: `MSD for element index N averaged to ~0`.
- **Pressure converged.** `calphy.log` should show the pressure cycles ending well
  before `md.n_cycles`. If it hit the limit the run raised
  `Pressure did not converge after MD runs, maybe change lattice_constant and try?`.
  Rerun, give a better `lattice_constant`, or pass a pre-equilibrated data file.
- **Iterations agree.** With `n_iterations > 1`, `error` should be a few 1e-4 eV/atom
  or less for 25000-step switching. An outlier iteration shows up as a large error.
- **Temperature is classical.** Below about the Debye temperature the classical
  result misses zero-point effects. Use `mode: fe-qtb` for solids.

## `mode: fe-qtb`

Same workflow with the Dammak quantum thermal bath (`fix qtb`) as sampler in every
stage and the quantum harmonic Einstein crystal as reference. Solid only; needs the
LAMMPS `QTB` package (the macOS conda-forge build lacks it, check `lmp -h`).
Set `quantum_thermal_bath.f_max` above the highest phonon frequency: 30 THz for
simple metals, 100+ for hydrides. `equilibration_control` is ignored in this mode.

## Combining results

Differences between two `fe` runs (two phases, two potentials, two compositions)
are valid only when both used the same `n_switching_steps`, system size, and
pressure, and ideally the same `md.seed` policy. Errors add in quadrature.

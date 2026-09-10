---
name: calphy-analyse-results
description: >-
  Read and interpret calphy output: report.yaml fields, temperature_sweep.dat and
  pressure_sweep.dat, forward/backward switching files, logs, and the
  `calphy.postprocessing` helpers (`read_report`, `gather_results`,
  `find_transition_temperature`), including how to combine runs, propagate errors,
  and build a melting line or phase diagram. Use when a calphy run has finished and
  the task is to extract, check, plot, or aggregate its numbers.
---

# Analyse calphy results

Every calculation lives in `[<prefix>-]<mode>-<lattice>-<phase>-<T>-<P>/`. Units
are LAMMPS metal: eV/atom, Å, Å³, bar, K. All `.dat` files have `#` header lines
naming the columns, so `numpy.loadtxt(path, unpack=True)` works directly.

## report.yaml

```python
from calphy.postprocessing import read_report
r = read_report("fe-fcc-solid-500-0")       # FileNotFoundError if the run did not finish
```

| block.key | meaning |
|---|---|
| `input.temperature`, `input.pressure`, `input.lattice`, `input.element`, `input.concentration` | the state that was run |
| `average.vol_atom` | equilibrium volume per atom, Å³ |
| `average.spring_constant` | Einstein spring constant(s), eV/Å², space-separated string; solid only |
| `average.density` | number density 1/Å³; liquid only |
| `results.free_energy` | **the answer**, eV/atom. F at P = 0, G at finite P |
| `results.error` | standard error of the mean over `n_iterations`; exactly 0.0 for one iteration |
| `results.reference_system` | analytic reference free energy (Einstein crystal or UFM) |
| `results.einstein_crystal`, `results.com_correction` | solid reference pieces |
| `results.work` | reversible work of the switch |
| `results.dissipation` | mean irreversible work, signed; magnitude should be small and shrink with `n_switching_steps` |
| `results.pv` | pressure-volume term |
| `results.ts_dissipation`, `results.ts_dissipation_high` | `ts`/`tscale` only: max hysteresis of the sweep (clean ~1e-4) and whether it exceeded `tolerance.dissipation` |
| `results.mass_correction`, `results.entropy_contribution` | `composition_scaling` only |

`alchemy` and `composition_scaling` report a **difference** in `free_energy`, not
an absolute value. `melting_temperature` writes no report.yaml; parse `STATE: Tm =`
from `<identifier>.log` in the launch directory.

## Sweep files

```python
import numpy as np
T, F, Ferr = np.loadtxt("ts-fcc-solid-1200-0/temperature_sweep.dat", unpack=True)
P, G, Gerr = np.loadtxt("pscale-fcc-solid-1200-0/pressure_sweep.dat", unpack=True)
```

The first row is the direct `fe` result at T0 (error 0 there by construction);
error grows along the sweep. `ts.forward_<i>.dat` / `ts.backward_<i>.dat`
(`dU press vol lambda`, one row per MD step) let you check hysteresis:

```python
lf, ef = np.loadtxt("ts.forward_1.dat", usecols=(3, 0), unpack=True)
lb, eb = np.loadtxt("ts.backward_1.dat", usecols=(3, 0), unpack=True)
# plot ef vs lf and eb vs lb: the curves should lie on top of each other
```

For `fe`: `forward_<i>.dat` / `backward_<i>.dat` have `dU_sys dU_ref... lambda`.

## Aggregating many runs

```python
from calphy.postprocessing import gather_results
df = gather_results(".", extract_phase_prefix=True)
df[["calculation", "calculation_mode", "reference_phase", "temperature", "pressure",
    "free_energy", "free_energy_error", "dissipation", "ts_dissipation", "status"]]
```

One row per folder. For `ts` rows the `temperature`, `free_energy`,
`free_energy_error` cells hold the sweep arrays. `include_sweep_data=True` also
loads the raw forward/backward series (large; use `sweep_data_stride`).
`extract_phase_prefix=True` keeps `phase_name` from `folder_prefix`, used by the
phase-diagram helpers `clean_df` and `fix_composition_scaling`.

## Transition temperatures

```python
from calphy.postprocessing import find_transition_temperature
Tt = find_transition_temperature("ts-fcc-solid-1200-0", "ts-fcc-liquid-1200-0", fit_order=4, plot=True)
```

Fits both curves with a polynomial and returns the crossing. Warnings:
`free energy is being extrapolated!` (windows do not overlap) and
`It is likely there is no intersection of free energies`. Quote the crossing with
an error: combine `Ferr` of both curves at the crossing in quadrature and divide by
the slope difference (about 1e-4 eV/atom/K for metal melting).

## Combining results

- Differences (phase A minus phase B, potential B minus A, composition x2 minus x1)
  are valid when both runs share `n_switching_steps`, system size, and pressure.
  Add errors in quadrature.
- `F_B = F_A + ΔF_alchemy` (upsampling). Check once against a direct run.
- Melting line: repeat the two-sweep crossing at each pressure; fit to a Simon
  equation `Tm(P) = T0 (P/a + 1)^c` to compare with literature.
- Entropy and cp from a `ts` sweep: fit F(T) with a degree 4 to 6 polynomial,
  `S = -dF/dT`, `cp = T dS/dT`. Multiply eV/atom/K by `e * N_A` for J/mol/K.
  Use large cells and long sweeps; derivatives amplify noise.

## Phase-diagram workflow

`calphy_phase_diagram -i phases.yaml` expands a `phases:` description (binary systems
only) into per-phase input files with `phase_name` and `folder_prefix` set, one
entry per (composition, temperature), using `composition_scaling` off-stoichiometry.
Run those with `calphy`, then `gather_results(..., extract_phase_prefix=True)`,
`clean_df(df, reference_element)`, `fix_composition_scaling(dfdict, add_ideal_entropy=True)`
to get per-phase free-energy surfaces for a common-tangent construction. The
intermediate compositions from composition scaling lack mixing entropy unless
`add_ideal_entropy` is used.

## Quick quality gate for a directory of runs

```python
import yaml, glob, os
for folder in sorted(glob.glob("*-*-*-*-*/")):
    p = os.path.join(folder, "report.yaml")
    if not os.path.exists(p):
        print(f"{folder:45s} NO REPORT (failed or still running)"); continue
    r = yaml.safe_load(open(p))["results"]
    flags = []
    if abs(r.get("dissipation", 0)) > 1e-3: flags.append("dissipation")
    if r.get("ts_dissipation", 0) > 1e-3: flags.append("ts_dissipation")
    if r.get("error", 0) == 0: flags.append("no-error-bar")
    print(f"{folder:45s} F={r['free_energy']:.5f} ± {r['error']:.1e}  {' '.join(flags)}")
```

Then apply the mode-specific trust checklists in calphy-free-energy,
calphy-temperature-sweep, and calphy-melting-temperature before quoting a number.

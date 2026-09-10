---
name: calphy-temperature-sweep
description: Run calphy reversible scaling (`mode: ts`), direct temperature scaling (`mode: tscale`), or pressure scaling (`mode: pscale`) to get the free energy of one phase as a continuous function of temperature or pressure, and check the sweep for hidden phase transitions. Use for F(T) or G(P) curves, solid-solid transition temperatures, phase-diagram lines, specific heat, and for interpreting temperature_sweep.dat or pressure_sweep.dat.
---

# Free energy along T or P

## Which mode

| mode | what it does | use when |
|---|---|---|
| `ts` | `fe` at T0, then scales the Hamiltonian by λ so that the system samples T0/λ (reversible scaling, Freitas/de Koning). Needs `pair_style hybrid/scaled`. | default choice for F(T) |
| `tscale` | `fe` at T0, then ramps the real thermostat T0 to Tf. No `hybrid/scaled`. | potential or accelerator (Kokkos `-sf kk`) does not support `hybrid/scaled`; result is otherwise equivalent (example 08) |
| `pscale` | `fe` at P0, then ramps the barostat P0 to Pf at fixed T. | G(P) at one temperature |

All three run `n_iterations` forward and backward sweeps and write the integrated
curve with a standard-error column.

## Input

```yaml
calculations:
- element: Cu
  mass: 63.546
  lattice: fcc
  lattice_constant: 3.615
  repeat: [7, 7, 7]
  mode: ts                      # or tscale
  reference_phase: solid        # or liquid
  temperature: [1200, 1400]     # [T0, Tf]; T0 is where the direct fe is done
  pressure: 0
  pair_style: eam/alloy
  pair_coeff: '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000      # or [25000, 50000]: first for fe, second for the sweep
  n_iterations: 3
  phase_transition_detection:
    mode: adapt                 # ts only; protects the sweep from crossing a transition
  queue: {scheduler: local, cores: 4}
```

`pscale`: `temperature: 1200`, `pressure: [0, 100000]` (bar, so 0 to 10 GPa).

Rules:

- **Direction.** For a solid put T0 at the low end: the direct `fe` is most reliable
  deep in the stable range, and the sweep heats from there. For a liquid put T0 at
  the high end if the lower end approaches freezing; calphy sweeps in either
  direction.
- **Window.** Do not sweep a solid far above its melting point or a liquid far below
  it. Superheating of 100 to 200 K is usually survivable for 25000-step sweeps;
  more is not. `phase_transition_detection.mode: adapt` runs a cheap pre-scan and
  shrinks the window to the clean range; `stop` raises instead; `warn` only logs.
- **Steps.** The sweep length is the second `n_switching_steps` value. Wide windows
  need more steps: keep roughly 100 steps per Kelvin or more for production
  (25000 steps for a 200 K window is the example scale).
- **Sampling.** `lambda_schedule: uniform_temperature` spreads samples evenly in T.
  It does not change the integrated result, only the error profile. Default `linear`
  is fine for windows of a few hundred Kelvin.
- **Ensemble.** `npt: True` (default) sweeps at constant pressure and gives G(T).
  `npt: False` keeps the volume from the T0 equilibration and gives F(V,T).

## Output

Folder `ts-<lattice>-<phase>-<T0>-<P>/` (or `tscale-`, `pscale-`). Files:

| file | columns |
|---|---|
| `temperature_sweep.dat` | `temperature[K] free_energy[eV/atom] error[eV/atom]` |
| `pressure_sweep.dat` | `pressure[bar] free_energy[eV/atom] error[eV/atom]` |
| `report.yaml` | the direct `fe` result at T0 plus `results.ts_dissipation` |
| `ts.forward_<i>.dat`, `ts.backward_<i>.dat` | per-step `dU press vol lambda`, one row per MD step; large |
| `prescan.forward.dat`, `prescan_signals.png` | only with phase_transition_detection on |

```python
import numpy as np
T, F, Ferr = np.loadtxt("ts-fcc-solid-1200-0/temperature_sweep.dat", unpack=True)
```

## Trust checklist

- **`results.ts_dissipation` in report.yaml.** Clean sweeps give about 1e-4 eV/atom.
  Values above `tolerance.dissipation` (1e-3) trigger the log warning
  `The path is far from reversible, which usually means the structure changed partway`.
  The whole `temperature_sweep.dat` is then contaminated, not just the high end.
  Narrow the window or enable the structural checks.
- **Forward and backward agree.** Plot `dU` against `lambda` from
  `ts.forward_1.dat` and `ts.backward_1.dat`; a visible hysteresis loop or a kink
  means a transition happened.
- **The direct `fe` at T0 passed its own checks.** See calphy-free-energy. Everything
  in the sweep is anchored to it.
- **Error column** grows away from T0. If it exceeds what you need at Tf, add
  iterations or steps.
- **Solid stayed solid** across the window: check `conf.ts.forward_1.data` visually
  or with a structure identifier (pyscal, OVITO). The default melt check is off.
- **`tscale` vs `ts`** should agree within the error bars for the same system; a
  disagreement points to a problem with `hybrid/scaled` for that pair style.

## Transition temperatures from two sweeps

Run one `ts` per phase over the same window, then

```python
from calphy.postprocessing import find_transition_temperature
Tt = find_transition_temperature("ts-bcc-solid-500-0", "ts-fcc-solid-500-0", fit_order=4, plot=True)
```

It fits both curves and finds the crossing; it warns `free energy is being
extrapolated!` if the windows do not overlap and `It is likely there is no
intersection of free energies` if they run parallel. Both phases must be
mechanically stable across the whole window. For solid-liquid crossings see the
calphy-melting-temperature skill.

## Derived quantities

Entropy and heat capacity come from derivatives of a polynomial fit to F(T), so they
amplify noise. Use 4000 atoms, 50000 or more sweep steps, several iterations, and a
wide window (example 12 uses 400 to 1200 K for Cu and still plots cp/T).

```python
import numpy as np, scipy.constants as sc
T, F, _ = np.loadtxt("ts-fcc-solid-400-0/temperature_sweep.dat", unpack=True)
p = np.polyfit(T, F, 5)
S = -np.polyder(p, 1)                                    # S(T) = -dF/dT, eV/atom/K
cp = T * np.polyval(np.polyder(S, 1), T)                 # cp = T dS/dT, eV/atom/K
cp_JmolK = cp * sc.e * sc.N_A
```

State the fit order with the result; orders 4 to 6 are typical.

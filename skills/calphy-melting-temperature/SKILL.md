---
name: calphy-melting-temperature
description: >-
  Compute a melting point with calphy, either automatically with `mode:
  melting_temperature` or manually from solid and liquid `ts` sweeps whose
  free-energy curves cross, and decide whether the resulting Tm is trustworthy.
  Use for melting temperatures of single-component or alloy potentials, melting
  lines at pressure, and for diagnosing "curves do not cross", "Tm is not within
  range", or a Tm that disagrees with the literature.
---

# Melting temperature

Two routes. The automated mode is a wrapper around the manual one.

| route | when |
|---|---|
| `mode: melting_temperature` | one element, zero or fixed pressure, you want a number with minimal setup |
| two `mode: ts` runs (solid, liquid) + crossing | alloys, multi-phase solids, pressure series, full control over the window, or when the automated run fails |

## Automated: `mode: melting_temperature`

```yaml
calculations:
- element: Cu
  mass: 63.546
  repeat: [10, 10, 10]          # 4000 atoms; the example scale for converged Tm
  mode: melting_temperature
  pair_style: eam/alloy
  pair_coeff: '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000
  n_iterations: 1
  temperature: 1300              # centre of the first bracket, K (see note on `guess`)
  melting_temperature:
    step: 400                    # half-width of the bracket, K
    attempts: 5
  queue: {scheduler: local, cores: 4}
```

`lattice` and `temperature` may be omitted for one element: calphy looks up a
default structure and centres the bracket on the experimental melting point from
mendeleev. **In calphy 2.1.2 `melting_temperature.guess` is accepted by the
validator but never read**; the bracket centre is always `temperature`. Set
`temperature` to your guess. Give
`lattice` explicitly when the high-temperature solid is not the ground-state
structure (Ti: bcc melts, not hcp). At non-zero `pressure` supply `temperature` close to
the expected value; the mendeleev default is ambient.

What it does: clones the calculation into a solid `ts` and a liquid `ts` over
`[T - step, T + step]`, re-enables the melt and solidification checks that
are otherwise off, runs both sweeps, and finds where the curves cross. If the solid
melts it shifts the bracket down; if the liquid freezes it shifts up; if the crossing
lies outside the bracket it extrapolates and reruns, up to `attempts` times.

Output: **no report.yaml**. The result is in `<identifier>.log` in the launch
directory and in the two sub-folders `ts-<lattice>-solid-<Tlow>-<P>/` and
`ts-<lattice>-liquid-<Tlow>-<P>/`.

```bash
grep STATE melting_temperature-*.log
#  STATE: Temperature range of 900.000000-1700.000000 K
#  STATE: Tm = 1285.24 K +/- 0.24 K
```

`Found melting temperature = X +/- Y K` is the same number. The error is the
free-energy uncertainty at the crossing divided by the slope difference, so it is
tiny with `n_iterations: 1` and does **not** include systematic error.

## Manual: two `ts` sweeps

```yaml
calculations:
- element: Cu
  mass: 63.546
  lattice: fcc
  lattice_constant: 3.615
  repeat: [7, 7, 7]
  mode: ts
  reference_phase: solid
  temperature: [1200, 1400]
  pressure: 0
  pair_style: eam/alloy
  pair_coeff: '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000
  n_iterations: 3
  tolerance: {solid_fraction: 0.7}      # abort if the solid melts
  queue: {scheduler: local, cores: 4}
- element: Cu
  mass: 63.546
  lattice: fcc
  lattice_constant: 3.615
  repeat: [7, 7, 7]
  mode: ts
  reference_phase: liquid
  temperature: [1200, 1400]
  pressure: 0
  pair_style: eam/alloy
  pair_coeff: '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000
  n_iterations: 3
  tolerance: {liquid_fraction: 0.05}    # abort if the liquid freezes
  queue: {scheduler: local, cores: 4}
```

Run both (`calphy -i input.yaml`, or `calphy_kernel ... -k 0` and `-k 1`), then

```python
from calphy.postprocessing import find_transition_temperature
Tm = find_transition_temperature("ts-fcc-solid-1200-0", "ts-fcc-liquid-1200-0", fit_order=4, plot=True)
```

For alloys use a LAMMPS data file as `lattice` for the solid; the liquid can start
from the same file, calphy melts it at `temperature_high`.

## Choosing the window

- The window must contain Tm and both phases must survive it. Hysteresis of a
  500 to 1000 atom cell is 100 to 200 K, so a 400 K wide window centred on a decent
  guess is comfortable; 200 K is the minimum useful width.
- Both sweeps need the **same** window so the curves overlap; otherwise
  `find_transition_temperature` extrapolates and warns.
- If the first attempt does not cross: look at which curve is lower. Solid lower
  everywhere and the curves converging means Tm is above the window; fit and
  extrapolate to get a new guess, then rerun in a window around it.

## Trust checklist

- **Both sub-runs passed the sweep checks** in calphy-temperature-sweep:
  `results.ts_dissipation` near 1e-4 eV/atom in both `report.yaml` files. A solid
  sweep with dissipation of 1e-2 has melted; its Tm is meaningless. In automated mode
  the log then says `STATE: Tm unreliable, sweep dissipation too high`.
- **Liquid really melted** before the sweep. Check `average.density` in the liquid
  `report.yaml` is a few percent below the solid `1/vol_atom`, and that `msd.dat`
  grows linearly. A frozen "liquid" gives a spurious crossing or none. Fix with a
  higher `temperature_high`.
- **Crossing angle.** The two curves should cross at a clear angle (entropy of
  fusion ~1.1 kB per atom for metals gives a slope difference of ~1e-4 eV/atom/K).
  Near-parallel curves mean one phase is wrong.
- **Convergence.** Repeat with larger `repeat` and longer `n_switching_steps`. The
  example settings (4000 atoms, 25000 steps) give Tm within ~50 K of longer runs;
  publication work uses 50 ps switching and 3 to 5 independent repeats.
- **Reference values.** The Mishin Cu EAM (`Cu01.eam.alloy`) gives ~1285 K in calphy
  vs 1357 K experiment. A potential's Tm is a property of the potential; compare
  with other methods (coexistence) for that potential, not with experiment.
- **Pressure.** Zero-pressure Tm needs `pressure: 0` in both runs. For a melting
  line repeat at each pressure with windows around the expected Tm(P); the Simon
  equation from a previous point is a good guess for the next.

## Failure modes specific to this mode

| symptom | cause and fix |
|---|---|
| `Cannot guess start temperature for more than one species, please specify` | Alloy without `temperature`. Set `temperature`. |
| `Maximum number of tries reached` | Bracket never contained Tm. Widen `step`, improve `temperature`, raise `attempts`. |
| `From calculation, melting temperature is not within the selected range.` | Same as above; check which side. |
| `Solid and liquid free-energy curves are parallel at the crossing` | One phase is in the wrong state. Check the trust list. |
| Tm changed by 100+ K between calphy versions or settings | Compare `average.vol_atom`, `spring_constant`, `ts_dissipation` first. Nearly always one sweep crossed a transition or the system sizes differ. |
| `System melted, increase size or reduce temp!` at the start of the solid run | `temperature + step` is far above Tm. Lower `temperature`. |
| `Simulation folder ts-<lattice>-solid-<T>-<P> exists` mid-search | The bracket search revisited a window it had already tried (seen with tiny test settings). Remove the `ts-*` folders, start from a better `temperature`, use production step counts. |
| `Liquid system did not melt, maybe try a higher thigh temperature.` | Raise `temperature_high`. |

---
name: calphy-choose-mode
description: Decide which calphy calculation mode and settings answer a thermodynamics question (free energy at a state point, free energy vs temperature or pressure, melting point, solid-solid transition, phase diagram, potential comparison, composition dependence, specific heat) and whether calphy is the right tool at all. Use before writing an input file when the user states a physical goal rather than a mode.
---

# Choose the calphy mode

calphy computes absolute free energies by thermodynamic integration in LAMMPS.
Solid reference: Einstein crystal (Frenkel-Ladd). Liquid reference: Uhlenbeck-Ford
fluid. Every mode is built from two primitives: a direct switch at one state point
(`fe`) and a reversible-scaling sweep along T or P (`ts`, `tscale`, `pscale`).

## First: is calphy applicable?

Answer these before picking a mode. If any fails, say so and stop.

| requirement | why | if not |
|---|---|---|
| The potential runs in LAMMPS and its forces can be scaled (`fix adapt` / `hybrid/scaled`). Nearly all classical and most ML pair styles qualify. `fix external` / client-server potentials do not. | calphy scales the Hamiltonian during switching | Not possible |
| Solid: a crystal whose atoms vibrate about lattice sites (no diffusion, no molecular rotations). | Einstein crystal reference | Molecular crystals need constraints calphy does not have |
| Liquid: a single-scale atomic liquid, or a molecular liquid with the two-leg UFM setup. | UFM reference | Water-like liquids need the `uhlenbeck_ford_model` two-leg path |
| Temperature above roughly the Debye temperature for classical results. | Classical MD misses zero-point effects | Use `fe-qtb` for solids; no liquid equivalent |
| Multi-element solid: a LAMMPS data file with the atoms on their sites. | Built-in lattices are single element | Build the cell externally (ASE, pyscal, atomsk) |

## Decision table

| question | mode | notes |
|---|---|---|
| F or G of one phase at one (T, P) | `fe` | Fastest. `n_iterations: 3+` for an error bar. |
| Same, solid below ~0.5 Debye T, want zero-point effects | `fe-qtb` | Solid only. Needs LAMMPS `QTB` package. |
| F(T) of one phase across a range | `ts` | One `fe` at T0 then a sweep to Tf. Start at the **low** end for solids so the sweep does not begin in a superheated state. |
| F(T) but the potential cannot be wrapped in `hybrid/scaled` (Kokkos `-sf kk`, some ML styles) | `tscale` | Same output as `ts`, different mechanism. Slightly less accurate per step. |
| G(P) at fixed T | `pscale` | `pressure: [P0, Pf]` in bar. |
| Melting point of a one-component system, minimal setup | `melting_temperature` | Automated bracket search. Give `melting_temperature.step` wide enough to cover hysteresis (example uses 400 K). |
| Melting point with control, alloys, or non-zero pressure | two `ts` runs (solid, liquid) over the same window, find the crossing | Use `calphy.postprocessing.find_transition_temperature`. |
| Solid-solid transition (bcc/fcc, hcp/bcc) | two `ts` runs, one per structure, crossing | Both must stay mechanically stable across the window. |
| P-T melting line / phase diagram | repeat the two-`ts` recipe at several pressures | Or use the `calphy_phase_diagram` tooling and `phase_name` labels. |
| Specific heat, entropy | `ts` with a long window and large cell, then differentiate a polynomial fit of F(T) | Noise grows with each derivative. Example 12 uses 4000 atoms and 50000 switching steps and still plots cp/T. |
| Free-energy difference between two potentials for the same structure (upsampling an expensive potential from a cheap one) | `alchemy` | Two `pair_style`, two `pair_coeff`. Short switching suffices when potentials are similar. |
| F as a function of composition, or the cost of one substitution | `composition_scaling` | Does **not** include the configurational mixing entropy for intermediate compositions; endpoints are correct. |
| Effect of pressure on a solid-solid transition | `pscale` for each phase at fixed T, or `ts` at several pressures | |

## Settings that follow from the choice

- **System size**: 500 atoms for testing, 1000 to 4000 for production. Finite-size
  error of the solid reference is handled by the `com_correction`; liquids need the
  larger sizes more.
- **Switching length**: 25000 steps reproduces literature melting points to about
  50 K; 50000 or more for production. Converge it: plot F against
  `n_switching_steps`.
- **Iterations**: `n_iterations: 3` to 5 for a standard error. A single iteration
  reports `error: 0.0`.
- **Sweep window**: keep `ts` windows inside the stability range of the phase. A
  solid swept far above its melting point melts mid-sweep and the whole
  `temperature_sweep.dat` is wrong; `phase_transition_detection.mode: adapt` guards
  against this, or check `results.ts_dissipation` afterwards (clean is ~1e-4 eV/atom).
- **Pressure**: 0 bar gives F = G. Any finite pressure adds the `pv` term and the
  report is G.

## Hand-off

Once the mode is chosen, write the file with the calphy-input-file skill and run it
with the calphy-run skill. Mode-specific procedure and checks live in
calphy-free-energy, calphy-temperature-sweep, calphy-melting-temperature, and
calphy-alchemy.

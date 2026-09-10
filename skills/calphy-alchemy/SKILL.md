---
name: calphy-alchemy
description: >-
  Run calphy alchemical transformations: `mode: alchemy` to get the free-energy
  difference between two interatomic potentials for the same structure (upsampling
  a cheap potential to an expensive one, comparing potentials), and `mode:
  composition_scaling` to get the free-energy change with composition or the cost
  of substitutional defects. Use when the question is a free-energy difference
  between two Hamiltonians or two compositions rather than an absolute free energy.
---

# Alchemical and composition transformations

Both modes switch one Hamiltonian into another over `n_switching_steps` at fixed
(T, P) and report the reversible work as `free_energy`. There is no reference
system: the result is a **difference**, F(B) - F(A).

## `mode: alchemy`: potential A to potential B

```yaml
calculations:
- element: Cu
  mass: 63.546
  lattice: fcc
  lattice_constant: 3.615
  repeat: [5, 5, 5]
  mode: alchemy
  reference_phase: solid
  temperature: 600
  pressure: 0
  pair_style: [eam/fs, eam/alloy]                     # [from, to]
  pair_coeff:
    - '* * /abs/path/Cu1.eam.fs Cu'
    - '* * /abs/path/Cu01.eam.alloy Cu'
  n_equilibration_steps: 10000
  n_switching_steps: 25000
  n_iterations: 3
  queue: {scheduler: local, cores: 4}
```

Rules:

- Exactly two `pair_style` and two `pair_coeff` entries, in order from A to B.
  `pair_mode: overlay` is not allowed here.
- Equilibration is done with potential A. `npt: True` (default) switches at constant
  pressure; `npt: False` keeps the volume of A.
- Works for liquids too (`reference_phase: liquid`, `melting_cycle` applies).
- `pressure: None` is allowed for a fixed box.

Upsampling recipe (example 07): `F_B = F_A(fe run) + ΔF(alchemy run)`. The alchemy
switch converges with far fewer steps than a full Frenkel-Ladd switch when A and B
are similar, which is the point when B is an expensive ML potential. Validate once
by comparing with a direct `fe` run with B; example 07 agrees to ~0.3 meV/atom.

Output folder `alchemy-<lattice>-<phase>-<T>-<P>/`, `report.yaml` with
`results.free_energy` = ΔF, `results.work`, `results.error`, `results.dissipation`.
`forward_<i>.dat` / `backward_<i>.dat` columns: `dU_1 dU_2 lambda`.

## `mode: composition_scaling`: composition x1 to x2

```yaml
calculations:
- element: [Zr, Cu]                    # order = LAMMPS types 1, 2
  mass: [91.224, 63.546]
  lattice: /abs/path/ZrCu.data         # 1024 atoms, 512 Zr + 512 Cu
  mode: composition_scaling
  composition_scaling:
    output_chemical_composition:
      Cu: 532
      Zr: 492                          # total must equal the input structure
    # restrictions: ["Al-O"]          # forbid specific A->B transformations
  reference_phase: solid
  temperature: 800
  pressure: 0
  pair_style: eam/fs
  pair_coeff: '* * /abs/path/ZrCu.eam.fs Zr Cu'
  equilibration_control: berendsen
  n_equilibration_steps: 5000
  n_switching_steps: 5000
  n_iterations: 3
  folder_prefix: comp
  queue: {scheduler: local, cores: 4}
```

Rules:

- Every `pair_coeff` must begin `* *` (types are renumbered internally).
- Works with `pair_mode: overlay` potentials: all components are switched together.
- Elements in `output_chemical_composition` must exist in the potential; the total
  atom count must match the input structure.
- Randomly chosen atoms of the surplus species are transformed. `md.seed` fixes the
  choice; the result depends weakly on which atoms are picked, so use
  `n_iterations: 3` or more and consider several seeds for dilute changes.
- Tested for two elements only; three or more logs `Composition scaling is untested
  for more than 2 elements!`.
- `monte_carlo.n_swaps > 0` interleaves `fix atom/swap` moves to sample
  configurations (needs LAMMPS `MC` package).

Output: `report.yaml` with `results.free_energy` = ΔF between the two compositions
and two extra keys, `results.mass_correction` and `results.entropy_contribution`.
The transformed structure is written next to the input as `<lattice>.comp.data`.
Only the end-point ΔF is reported; calphy 2.1.2 does not write a per-composition
sweep file (older notebooks mention `composition_sweep.dat`, which no longer
exists). For a curve over composition run one calculation per target composition,
or use the phase-diagram workflow in calphy-analyse-results.

### What composition scaling does not include

The switch transforms atom identities on fixed sites, so the **configurational
mixing entropy** of the intermediate compositions is not sampled. End points are
exact; intermediate values are missing the ideal (or real) mixing term. Add
`-T S_mix` yourself if you need intermediate compositions, or run separate
end-point calculations. `calphy.postprocessing.fix_composition_scaling` has an
`add_ideal_entropy` option for the phase-diagram workflow.

### Substitution free energy (example 10)

ΔF of a single Zr to Cu swap in 1024-atom B2 ZrCu at 800 K: two direct `fe` runs
give 3.9 ± 0.1 meV/atom, one `composition_scaling` run gives 3.87 ± 0.01 meV/atom.
The alchemical route has ten times smaller error because the common noise cancels.

## Trust checklist

- `results.dissipation` small and shrinking with `n_switching_steps`.
- `error` (standard error over iterations) well below the ΔF you are resolving.
- For `alchemy`: the structure did not change phase during the switch. Potential B
  may not stabilise the structure that A does; look at `conf.*` files.
- For `composition_scaling`: the number of transformed atoms is small relative to the
  cell (a few percent) unless you have checked convergence with cell size.
- Same `n_switching_steps`, size, and pressure in any `fe` run you add the result to.

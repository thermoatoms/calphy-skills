---
name: calphy-install
description: Install calphy and a LAMMPS binary that has the packages calphy needs, then verify the setup with a preflight check. Use when setting up calphy for the first time, when `lmp` cannot be found, when a run fails with a missing LAMMPS package or a pair_style/fix "unrecognized" error, or when enabling the optional pylammpsmpi library backend.
---

# Install calphy

calphy is a Python package that drives an external LAMMPS binary (`lmp`) as a
subprocess. Installing calphy alone is not enough: an `lmp` binary with the right
packages must be reachable. Work through the steps in order and stop at the first
check that fails.

## 1. Pick an install route

| situation | route |
|---|---|
| Laptop or workstation, no LAMMPS yet | conda-forge (step 2a). Gives calphy, `lmp`, and `mpirun` in one environment. |
| Cluster with a LAMMPS module | pip or conda for calphy, then point calphy at the module's `lmp` (step 2b). |
| Need ML potentials (ACE, SNAP, MLIAP), MEAM, or KIM and the conda `lmp` lacks them | compile LAMMPS (step 2c). |
| Windows | use WSL, then follow the Linux route. |

Python 3.10 or newer is required.

## 2a. conda-forge route

```bash
mamba create -n calphy -c conda-forge calphy lammps openmpi -y   # or conda
conda activate calphy
```

If mamba/conda is missing, install miniforge first. Do not `pip install lammps`:
the conda-forge `lammps` package is what provides `lmp`.

## 2b. Existing LAMMPS binary route

```bash
pip install calphy              # or: conda install -c conda-forge calphy
module load lammps              # site specific
export CALPHY_LAMMPS_EXECUTABLE=$(which lmp)      # or the module's binary path
export CALPHY_MPI_EXECUTABLE=$(which mpirun)      # only needed for queue.cores > 1
```

The same two settings can go in the input file instead, as `lammps_executable`
and `mpi_executable` inside the calculation block. Resolution order is the input
key, then the environment variable, then `lmp` / `mpirun` on PATH.

## 2c. Compile LAMMPS

Use a recent stable release from https://github.com/lammps/lammps/releases.

```bash
cd lammps-*/ && mkdir build && cd build
cmake -D BUILD_MPI=ON \
      -D PKG_MANYBODY=ON \
      -D PKG_EXTRA-FIX=ON \
      -D PKG_EXTRA-PAIR=ON \
      -D PKG_MC=ON \
      -D PKG_QTB=ON \
      ../cmake
make -j
```

Add potential packages as needed: `-D PKG_ML-PACE=ON` (ACE), `-D PKG_ML-SNAP=ON`,
`-D PKG_MEAM=ON`, `-D PKG_KIM=ON`, `-D PKG_ML-IAP=ON`. Put the resulting `lmp` on
PATH or set `CALPHY_LAMMPS_EXECUTABLE`.

## 3. Which LAMMPS packages calphy needs

| calphy feature | package | provides |
|---|---|---|
| any potential | `MANYBODY` plus the potential's own package | `pair_style eam/alloy`, `meam`, `pace`, ... |
| solid free energy, `ts`, `tscale` | `EXTRA-FIX` | `fix ti/spring` |
| liquid free energy, `melting_temperature` | `EXTRA-PAIR` | `pair_style ufm`, `pair_style hybrid/scaled` |
| `monte_carlo.n_swaps > 0` | `MC` | `fix atom/swap` |
| `mode: fe-qtb` | `QTB` | `fix qtb` |

calphy runs `lmp -h` before the first simulation (the preflight) and fails with a
message naming the missing package. `CALPHY_SKIP_PREFLIGHT=1` bypasses it; only do
that when the binary is known to be fine but `lmp -h` cannot run (some MPI-only
wrappers).

## 4. Verify

Resolve this skill's directory from the `SKILL.md` path supplied by the agent host,
then run the bundled checker:

```bash
bash <calphy-install-skill-directory>/scripts/check_setup.sh
```

It reports the calphy version, which `lmp` will be used, and which of the five
packages the binary provides. Interpret the output:

- `calphy: not importable` means the Python environment is wrong or not activated.
- `lmp: not found` means none of the three resolution steps worked. Set
  `CALPHY_LAMMPS_EXECUTABLE` to an absolute path.
- A package listed as `missing` means the corresponding feature will fail preflight.
  Use another build or compile with that package on.

Equivalent manual checks:

```bash
python -c "import calphy; print(calphy.__version__)"
which lmp || echo "$CALPHY_LAMMPS_EXECUTABLE"
lmp -h | grep -E "ti/spring|ufm|hybrid/scaled|atom/swap|qtb"
```

## 5. Smoke test

Run a tiny solid free-energy calculation. It takes 15 s to 2 min on 4 cores.

```bash
mkdir calphy-smoke && cd calphy-smoke
cp <calphy-install-skill-directory>/scripts/smoke_input.yaml input.yaml
# a Cu EAM potential is needed; the calphy repository ships one at
# examples/potentials/Cu01.eam.alloy. Adjust pair_coeff if you use another file.
calphy_kernel -i input.yaml -k 0
```

Success looks like a folder `fe-fcc-solid-500-0/` containing `report.yaml` with a
`results.free_energy` value near -3.644 eV/atom for Cu at 500 K (scatter of a few meV
is normal at these short settings). If the run fails,
the LAMMPS error is at the end of the newest `*.seglog` file in that folder.

## 6. Optional: library backend

Only needed for `execution_mode: library`, which drives an in-memory LAMMPS
through pylammpsmpi. Requirements: `pip install calphy[library]` and the `lammps`
Python module plus `liblammps` from the **same** LAMMPS version. conda-forge
`lammps` ships both.

```bash
python -c "from lammps import lammps; lammps(); print('lammps python module OK')"
python -c "from pylammpsmpi import LammpsLibrary; print('pylammpsmpi OK')"
```

If the first check raises `LAMMPS Python module installed for LAMMPS version X, but
shared library is version Y`, the versions are mixed. Under pylammpsmpi this shows
up as a run that hangs at startup with no output, not as a clean error. Reinstall
both from conda-forge in one step.

## Known gotchas

- Installing `lammps` into an environment that already has a compiler toolchain can
  downgrade that toolchain. Keep LAMMPS in its own environment and put its `bin` on
  PATH if that happens.
- An editable install (`pip install -e .`) of a different calphy checkout wins over
  the one in the current directory when Python is run from elsewhere. Check with
  `python -c "import calphy; print(calphy.__file__)"`.
- Singularity users: `singularity pull --arch amd64 library://sebastianhavens/calphy/calphy:latest`
  and run `singularity exec --bind $PWD --pwd $PWD image.sif calphy_kernel -i input.yaml -k 0`
  with `queue.scheduler: local`. Host OpenMPI must be at least 4.1.2.

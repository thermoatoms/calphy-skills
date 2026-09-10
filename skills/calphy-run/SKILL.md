---
name: calphy-run
description: >-
  Launch, monitor, and rerun calphy calculations: `calphy_kernel` for one
  calculation in the foreground, `calphy` to submit every entry through the local,
  SLURM, or SGE scheduler, hand-written batch scripts, MPI core counts, the
  pylammpsmpi library backend, the in-process Python API, and reading progress from
  calphy.log. Use when a valid input.yaml exists and the task is to run it on a
  laptop or cluster, check on a running job, estimate runtime, or rerun a failed one.
---

# Run calphy

## The two commands

| command | what it does |
|---|---|
| `calphy_kernel -i input.yaml -k N` | Runs calculation N (0-based index into `calculations:`) in the foreground, in the current directory. This is the worker. |
| `calphy -i input.yaml` | Writes one submission script per calculation (`<identifier>.sub`) and submits each via `queue.scheduler`. Each script just calls `calphy_kernel -i input.yaml -k N`. |

Both accept `--validate` for full validation of all entries at parse time.
`calphy -v` prints the version. There is no dry run and no restart flag.

Always run from the directory that should hold the output folders, with the
environment activated, and with absolute potential paths in the input.

## Local machine

```bash
calphy_kernel -i input.yaml -k 0                 # foreground; log at ./<folder>/calphy.log
nohup calphy_kernel -i input.yaml -k 0 > k0.out 2>&1 &
calphy -i input.yaml                              # scheduler: local -> one background process per entry
```

`queue.cores` sets the MPI ranks: `cores: 4` runs `mpirun -np 4 lmp ...`. On one
node do not exceed physical cores, and do not launch several jobs that together
exceed them; calphy does not pin processes. With `scheduler: local`, stdout and
stderr of each job go to `local.out` / `local.err` in the launch directory.

## Cluster (SLURM or SGE)

```yaml
  queue:
    scheduler: slurm
    cores: 40
    jobname: cu_fe
    walltime: "23:50:00"
    queuename: standard
    memory: 3GB                # written as --mem (SLURM), i.e. per node/job
    commands:
      - source ~/.bashrc
      - conda activate calphy
      - module load lammps
      - export CALPHY_LAMMPS_EXECUTABLE=$(which lmp)
    options:                   # extra scheduler directives, key: value
      account: myproject
```

`calphy -i input.yaml` then runs `sbatch <identifier>.sub` for each entry and
prints `submitting <jobname>`; failures print `Failed to submit!` with the sbatch
output. Job stdout/stderr land in `<identifier>.sub.slurm.out` / `.slurm.err`.

Equivalent hand-written script, useful when the site needs options calphy does not
expose:

```bash
#!/bin/bash
#SBATCH --job-name=cu_fe
#SBATCH --time=23:50:00
#SBATCH --partition=standard
#SBATCH --ntasks=40
#SBATCH --mem-per-cpu=3GB
source ~/.bashrc
conda activate calphy
module load lammps
export CALPHY_LAMMPS_EXECUTABLE=$(which lmp)
export CALPHY_MPI_EXECUTABLE=$(which srun)   # if mpirun is not the launcher on this site
calphy_kernel -i input.yaml -k 0
```

Keep `queue.scheduler: local` in the input when you submit this way, and use one
script per `-k`. A Singularity image is invoked the same way:
`singularity exec --bind $PWD --pwd $PWD calphy.sif calphy_kernel -i input.yaml -k 0`.

## How long will it take

Wall time scales with `natoms * total_steps / cores`. Total steps per calculation,
roughly:

| mode | steps |
|---|---|
| `fe` | pressure convergence (k × `md.n_small_steps`, k usually 1 to 10) + spring-constant cycles + `n_equilibration_steps` + `n_iterations` × 2 × `n_switching_steps` |
| `ts`, `tscale`, `pscale` | the `fe` total + `n_iterations` × (2 × sweep steps + 2 × equilibration) |
| `melting_temperature` | two `ts` runs per attempt |

Reference point: 500 Cu atoms, EAM, 2500 equilibration and 5000 switching steps,
2 iterations, 4 cores: `fe` 15 s, `ts` 35 s. Production settings (4000 atoms,
25000 to 50000 steps, 3 iterations) are hours on 40 cores.

## Monitor a run

```bash
tail -f <folder>/calphy.log
```

Stages appear in order: seed, `Melt detection is DISABLED` warning, pressure
convergence lines (`At count N mean pressure is ...`), spring-constant lines
(`At count N mean k is ...`), then per-iteration switching, then reversible
scaling for `ts`. A complete run has `report.yaml` and `metadata.yaml`.

Stuck-run diagnostics:

- No `calphy.log` at all: the input failed validation. Read `local.err` or the
  scheduler `.err` file.
- Log stops after the potential lines: LAMMPS died. Read the newest
  `<folder>/calphy.seg<k>.log`; the `ERROR:` line is at the end.
- Pressure lines cycling towards `md.n_cycles` (100): pressure is not converging.
  See calphy-troubleshoot.
- Library mode with no output at all: `lammps` module and `liblammps` version
  mismatch; see calphy-install.

## Rerun or resume

There is no resume. calphy refuses to reuse an output folder:
`Simulation folder ... exists. Please remove and run again!`. Either delete the
folder or set `folder_prefix` to get a new name. The exact seed used is written back
into `<folder>/input_file.yaml`; rerunning that file reproduces the LAMMPS input
stream (bitwise-identical trajectories also need the same binary, core count, and
hardware).

Finished stages cannot be reused, but the equilibrated structure
`conf.equilibration.data` can be fed to a new calculation as `lattice` (with
`melting_cycle: False` for liquids) to skip the melting cycle and shorten
equilibration.

## Library backend (pylammpsmpi)

`execution_mode: library` keeps one LAMMPS instance alive in memory instead of
running `lmp` per segment. Same commands, same results. Needs
`pip install calphy[library]` and a matching `lammps` Python module (calphy-install
step 6). `queue.cores` becomes the MPI size inside pylammpsmpi; `lammps_executable`
and the preflight check are not used. Python-coupled ML-IAP models are activated
automatically when `lammps.mliap` is importable.

## Python API (in-process)

```python
from calphy.input import read_inputfile
import calphy.queuekernel as cq

calcs = read_inputfile("input.yaml")          # list of validated Calculation objects
job = cq.setup_calculation(calcs[0])          # creates the output folder
job = cq.run_calculation(job)                 # blocks until done
job.report["results"]["free_energy"], job.fe, job.w, job.pv
```

Run one calculation per process; several in one interpreter mix their log
handlers. `read_inputfile` writes the generated structure file into the current
directory.

## Environment variables

| variable | purpose |
|---|---|
| `CALPHY_LAMMPS_EXECUTABLE` | path to `lmp` when not on PATH and not in the input |
| `CALPHY_MPI_EXECUTABLE` | MPI launcher for `cores > 1` (default `mpirun`) |
| `CALPHY_SKIP_PREFLIGHT=1` | skip the `lmp -h` capability check |
| the variable named by `materials_project.api_key`, e.g. `MP_API_KEY` | Materials Project key when `lattice: mp-NNN` |

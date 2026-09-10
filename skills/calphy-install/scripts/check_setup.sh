#!/usr/bin/env bash
# Report whether calphy and a suitable LAMMPS binary are available.
# Exit code 0 when calphy imports and lmp provides every package calphy uses.

status=0

if ver=$(python -c "import calphy, sys; print(calphy.__version__)" 2>/dev/null); then
  echo "calphy: $ver ($(python -c 'import calphy,os; print(os.path.dirname(calphy.__file__))'))"
else
  echo "calphy: not importable in $(command -v python)"
  status=1
fi

if [ -n "$CALPHY_LAMMPS_EXECUTABLE" ]; then
  lmp_bin="$CALPHY_LAMMPS_EXECUTABLE"; src='$CALPHY_LAMMPS_EXECUTABLE'
elif command -v lmp >/dev/null 2>&1; then
  lmp_bin="$(command -v lmp)"; src='PATH'
else
  echo "lmp: not found (checked \$CALPHY_LAMMPS_EXECUTABLE and PATH)"
  exit 1
fi
echo "lmp: $lmp_bin (from $src)"

help=$("$lmp_bin" -h 2>/dev/null) || { echo "lmp -h failed to run"; exit 1; }
echo "$help" | sed -n 's/^\(Large-scale Atomic.*\)$/version: \1/p' | head -1

check() {  # label, grep pattern, package name
  if echo "$help" | grep -qE "$2"; then
    echo "  $1: ok"
  else
    echo "  $1: missing (needs LAMMPS package $3)"
    status=1
  fi
}
echo "packages:"
check "fix ti/spring (solid, ts, tscale)" "ti/spring" "EXTRA-FIX"
check "pair ufm (liquid)" "(^|[[:space:]])ufm([[:space:]]|$)" "EXTRA-PAIR"
check "pair hybrid/scaled (liquid, ts)" "hybrid/scaled" "EXTRA-PAIR"
check "fix atom/swap (monte_carlo)" "atom/swap" "MC"
check "fix qtb (fe-qtb)" "(^|[[:space:]])qtb([[:space:]]|$)" "QTB"
check "pair eam/alloy (MANYBODY)" "eam/alloy" "MANYBODY"

if [ -n "$CALPHY_MPI_EXECUTABLE" ]; then
  echo "mpirun: $CALPHY_MPI_EXECUTABLE (from \$CALPHY_MPI_EXECUTABLE)"
elif command -v mpirun >/dev/null 2>&1; then
  echo "mpirun: $(command -v mpirun)"
else
  echo "mpirun: not found (only needed for queue.cores > 1)"
fi
exit $status

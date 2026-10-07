#!/usr/bin/env bash
# Runs every simulation in the project and checks the expected outcome.
# Needs Verilator 5.x (--binary). Usage: bash run_all.sh   (Linux, macOS or WSL)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v verilator >/dev/null 2>&1 || { echo "ERROR: verilator 5.x not found (e.g. sudo apt install verilator)" >&2; exit 1; }
SV=systemverilog; SVA=sva; AN=anvil/generated; T=tests
pass=0; bad=0
run() { # run <expect pass|fail> <top> <label> <files...>
  local expect=$1 top=$2 label=$3; shift 3
  local dir; dir=$(mktemp -d)
  local out comp
  comp=$(verilator --binary --assert --timing -Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTH \
      --top-module "$top" --Mdir "$dir" "$@" 2>&1) || { echo "WRONG [$expect] $label (did not compile)"; echo "$comp" | tail -5; bad=$((bad+1)); rm -rf "$dir"; return; }
  out=$("$dir/V$top" 2>&1); local rc=$?
  local failed=0
  if [ $rc -ne 0 ] || echo "$out" | grep -qE "FAIL|%Error|mismatch|Assertion failed"; then failed=1; fi
  if { [ "$expect" = pass ] && [ $failed -eq 0 ]; } || { [ "$expect" = fail ] && [ $failed -eq 1 ]; }; then
    echo "ok    [$expect] $label"; pass=$((pass+1))
  else
    echo "WRONG [$expect] $label"; echo "$out" | tail -5; bad=$((bad+1))
  fi
  rm -rf "$dir"
}
run pass dot_product_tb             "SV functional"            $SV/dot_product.sv $SV/testbench.sv
run pass dot_product_tb             "SV + SVA properties"      $SV/dot_product.sv $SVA/properties.sv $SVA/testbench_sva.sv
run pass tb_dot_product_anvil       "Anvil functional"         $AN/dot_product_anvil.sv $T/tb_dot_product_anvil.sv
run pass dot_product_equivalence_tb "SV vs Anvil equivalence"  $SV/dot_product.sv $AN/dot_product_anvil.sv $SVA/testbench_equivalence.sv
run fail dot_product_tb             "Broken SV, functional"    $SV/dot_product_broken.sv $SV/testbench.sv
run fail dot_product_tb             "Broken SV, SVA catches P3" $SV/dot_product_broken.sv $SVA/properties.sv $SVA/testbench_sva.sv
run fail dot_product_equivalence_tb "Wrong-but-timing-safe Anvil caught" $SV/dot_product.sv $AN/dot_product_drop_product_anvil.sv $SVA/testbench_equivalence.sv
echo "$pass as expected, $bad unexpected"
[ $bad -eq 0 ]

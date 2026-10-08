# Anvil Vector Dot-Product Accelerator

This repository contains one handwritten SystemVerilog implementation, its
assertion-based verification, and a sequential implementation written in
Anvil HDL. The two implementations are tested with the same transaction
vectors by the differential testbench.

## Run everything

```bash
bash run_all.sh
```

**Requirements:** Verilator 5.x (Linux, macOS, or WSL). The script exits early with a clear message if Verilator is not installed.

It runs seven simulations and checks each outcome. Expected output:

```text
ok    [pass] SV functional
ok    [pass] SV + SVA properties
ok    [pass] Anvil functional
ok    [pass] SV vs Anvil equivalence
ok    [fail] Broken SV, functional
ok    [fail] Broken SV, SVA catches P3
ok    [fail] Wrong-but-timing-safe Anvil caught
7 as expected, 0 unexpected
```

`[pass]` runs must finish with no failures. `[fail]` runs are the deliberate negative controls and must be caught by a property or by the differential test.

## Quick Evidence

The runs were first made in EDA Playground (Verilator 5.044) and are summarized in
`results/SIMULATION_RESULTS.md`. `run_all.sh` was also run in a clean GitHub Codespace
(Ubuntu, Verilator 5.020) with the result shown above.

| Evidence | Expected result |
|---|---|
| `systemverilog/dot_product.sv` + `systemverilog/testbench.sv` | PASS |
| `systemverilog/dot_product.sv` + `sva/testbench_sva.sv` | PASS |
| `systemverilog/dot_product_broken.sv` + `sva/testbench_sva.sv` | FAIL at P3, as intended |
| `anvil/generated/dot_product_anvil.sv` + `tests/tb_dot_product_anvil.sv` | PASS |
| `systemverilog/dot_product.sv` + `anvil/generated/dot_product_anvil.sv` + `sva/testbench_equivalence.sv` | PASS |
| `systemverilog/dot_product.sv` + `anvil/generated/dot_product_drop_product_anvil.sv` + `sva/testbench_equivalence.sv` | FAIL, as intended |

## Repository Structure

**SystemVerilog (Part A)**

- `systemverilog/dot_product.sv` — four-lane reference accelerator.
- `systemverilog/testbench.sv` — basic functional tests, including zero-length behavior.
- `systemverilog/dot_product_broken.sv` — negative design with the accumulator
  reset intentionally removed for the Part B demonstration.

**SVA (Part B)**

- `sva/properties.sv` — the six reusable properties (P1–P6).
- `sva/PROPERTY_RATIONALE.md` — purpose and failure meaning for each property.
- `sva/testbench_sva.sv` — handwritten-SV tests with those properties.
- `sva/testbench_anvil_sva.sv` — the same property intents adapted to the
  Anvil-generated interface.
- `sva/testbench_equivalence.sv` — one matched-stimulus testbench that drives
  both implementations through protocol adapters, checks expected results,
  and compares the two results.

**Anvil (Part C)**

- `anvil/dot_product.anvil` — source for the correct sequential Anvil design.
- `anvil/generated/dot_product_anvil.sv` — compiler output; do not edit by
  hand, regenerate it from the source.
- `tests/tb_dot_product_anvil.sv` — standalone functional test for generated
  Anvil SV.
- `anvil/dot_product_drop_product.anvil` — intentional wrong-but-timing-correct
  negative-control source; it drops the product term.
- `anvil/generated/dot_product_drop_product_anvil.sv` — generated SV for that
  negative-control source.
- `anvil/dot_product_rejected.anvil` — small design that Anvil's timing-safety
  check rejects (observation 1).

**Observations, report, and results**

- `observations/` — the three assignment observations (see below).
- `report/Anvil_Vector_Dot_Product_Report.pdf` — the report.
- `results/SIMULATION_RESULTS.md` — concise record of passing and expected-failing runs.
- `PROVENANCE.md` — what was reused, what AI assisted with, and what I did myself.
- `run_all.sh` — runs every simulation and checks the expected outcome.

## What the differential test compares

The verification flow is:

`SystemVerilog → SVA → Anvil source → generated SV → tests`

Part A establishes the reference behavior. Part B states protocol and state
invariants and demonstrates that the broken SV design is caught. Part C
expresses a sequential accelerator in Anvil; the compiler lowers it to SV.

The SystemVerilog design is four-lane and the Anvil design is sequential, so
their cycle timing, lane masks, and accumulator state are not directly
comparable. The differential test therefore sends each logical command and
ordered element sequence to both modules through adapters, checks each result
independently against the expected dot product, and compares command
acceptance and element handshake counts, result values, and tags. It does not
require cycle-by-cycle equality or equivalent internal lane state. This is
itself a finding: Anvil's timing-safety model fits a sequential port naturally,
but it does not preserve a parallel microarchitecture's internal state.

## Regenerating the Anvil output

Anvil compiler revision used: `d138cabedbfc3b65c08249ce6a55cb90dad959da`.

From the Anvil compiler checkout:

```text
dune exec anvil -- -just-check <path-to-repo>/anvil/dot_product.anvil
dune exec anvil -- <path-to-repo>/anvil/dot_product.anvil > <path-to-repo>/anvil/generated/dot_product_anvil.sv
```

**Windows note:** PowerShell's `>` writes UTF-16, which Verilator on Linux cannot
read. Run the commands from WSL or Git Bash, or convert afterward:

```text
iconv -f UTF-16 -t UTF-8 file.sv | sed 's/\r$//' > file_utf8.sv
```

The committed generated files are UTF-8.

## EDA Playground

Put the correct handwritten SV and correct generated Anvil SV in the Design
pane, put `sva/testbench_equivalence.sv` in the Testbench pane, and run
Verilator with `--assert`. Substitute the negative generated SV only when
demonstrating that the differential test fails.

## Observations

See [`observations/compiler_trace.md`](observations/compiler_trace.md) for a
source-to-compiler-pass-to-generated-RTL trace of the multiplication.

The three assignment observations are documented in
[`observations/rejected_by_anvil.md`](observations/rejected_by_anvil.md),
[`observations/accepted_but_wrong.md`](observations/accepted_but_wrong.md),
and [`observations/compiler_trace.md`](observations/compiler_trace.md).

## Provenance

See [`PROVENANCE.md`](PROVENANCE.md).
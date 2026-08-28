# Anvil Vector Dot-Product Accelerator

This repository contains one handwritten SystemVerilog implementation, its
assertion-based verification, and a sequential implementation written in
Anvil HDL.  The two implementations are tested with the same transaction
vectors by the differential testbench.

## Repository Structure

**SystemVerilog (Part A)**

- `systemverilog/dot_product.sv` — four-lane reference accelerator.
- `systemverilog/testbench.sv` — basic functional tests for that module.
- `systemverilog/dot_product_broken.sv` — negative design with the accumulator
  reset intentionally removed for the Part B demonstration.

**SVA (Part B)**

- `sva/properties.sv` — the six reusable properties (P1–P6).
- `sva/PROPERTY_RATIONALE.md` — beginner-friendly purpose and failure meaning
  for each property.
- `sva/testbench_sva.sv` — handwritten-SV tests with those properties.
- `sva/testbench_anvil_sva.sv` — the same property intents adapted to the
  Anvil-generated interface.
- `sva/testbench_equivalence.sv` — one matched-stimulus testbench that drives
  both implementations through protocol adapters, checks expected results,
  and compares the two results.  It deliberately does not require identical
  cycle timing because one design is four-lane and the other is sequential.

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

The verification flow is:

`SystemVerilog → SVA → Anvil source → generated SV → tests`

Part A establishes the reference behavior. Part B states protocol and state
invariants and demonstrates that the broken SV design is caught. Part C
expresses a sequential accelerator in Anvil; the compiler lowers it to SV.
The differential test sends each logical command and ordered element sequence
to both modules through adapters. It checks each result independently against
the expected dot product, then compares result values and tags. It does not
require cycle-by-cycle equality or equivalent internal lane state.

## Useful commands

From the Anvil compiler checkout (`D:\anvil`):

```text
dune exec anvil -- -just-check D:\anvil-vector-dot-product\anvil\dot_product.anvil
dune exec anvil -- D:\anvil-vector-dot-product\anvil\dot_product.anvil > D:\anvil-vector-dot-product\anvil\generated\dot_product_anvil.sv
```

In EDA Playground, put the correct handwritten SV and correct generated Anvil
SV in the Design pane, put `sva/testbench_equivalence.sv` in the Testbench
pane, and run Verilator with `--assert`.  Substitute the negative generated
SV only when demonstrating that the differential test fails.

See [`observations/compiler_trace.md`](observations/compiler_trace.md) for a
source-to-compiler-pass-to-generated-RTL trace of the multiplication.

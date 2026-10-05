# Simulation Results Summary

All simulations were run in EDA Playground with Verilator 5.044 and
`--assert` enabled where assertions were present.

## Passing Runs

| Run | Design files | Testbench | Result |
|---|---|---|---|
| Handwritten SV functional | `systemverilog/dot_product.sv` | `systemverilog/testbench.sv` | PASS |
| Handwritten SV with SVA | `systemverilog/dot_product.sv` | `sva/testbench_sva.sv` | PASS |
| Anvil-generated SV functional | `anvil/generated/dot_product_anvil.sv` | `tests/tb_dot_product_anvil.sv` | PASS |
| SV vs Anvil equivalence | `systemverilog/dot_product.sv`, `anvil/generated/dot_product_anvil.sv` | `sva/testbench_equivalence.sv` | PASS |

The equivalence run passed the following transaction cases:

| Case | Expected | Observed |
|---|---:|---|
| Length 1 | 63 | SV=63, Anvil=63 |
| Length 0 | 0 | SV=0, Anvil=0 |
| Length 2 with zero operands | 0 | SV=0, Anvil=0 |
| Length 3 partial group | 32 | SV=32, Anvil=32 |
| Length 4 | 70 | SV=70, Anvil=70 |
| Multiple command A | 30 | SV=30, Anvil=30 |
| Multiple command B | 50 | SV=50, Anvil=50 |
| Max operands with backpressure | 260100 | SV=260100, Anvil=260100 |

## Expected-Failing Runs

| Run | Design files | Testbench | Expected failure |
|---|---|---|---|
| Broken SV functional | `systemverilog/dot_product_broken.sv` | `systemverilog/testbench.sv` | Stale accumulator causes wrong results |
| Broken SV with SVA | `systemverilog/dot_product_broken.sv` | `sva/testbench_sva.sv` | P3 fails: accumulator not zero after new command |
| Wrong Anvil differential | `systemverilog/dot_product.sv`, `anvil/generated/dot_product_drop_product_anvil.sv` | `sva/testbench_equivalence.sv` | Anvil result mismatch: got 9, expected 63 |

## Key Evidence Lines

Correct SV vs correct Anvil:

```text
PASS: matched stimulus, both property suites, and differential comparison passed.
```

Broken SV caught by SVA:

```text
FAIL P3: accumulator not zero after new command accepted
```

Timing-safe but functionally wrong Anvil variant:

```text
Anvil result mismatch: got 9/tag1 expected 63/tag1
```


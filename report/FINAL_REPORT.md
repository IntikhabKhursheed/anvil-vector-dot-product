# Anvil Vector Dot-Product Accelerator

## Executive summary

This project implements and verifies a vector dot-product accelerator in two
ways: a handwritten four-lane SystemVerilog reference and a sequential Anvil
HDL implementation. Both implementations use the same logical command,
ordered element stream, tag, and result protocol. A matched-stimulus
differential testbench checks each result against an independent expected value
and then checks agreement between the two implementations.

## Part A: SystemVerilog reference

`systemverilog/dot_product.sv` is a four-lane accelerator with IDLE, LOAD,
REDUCE, and OUTPUT states. It supports partial final groups, a 20-bit
accumulator, ready/valid handshakes, output backpressure, and tagged results.
`systemverilog/testbench.sv` provides the basic functional tests.

`systemverilog/dot_product_broken.sv` is a negative control. It removes the
command-time accumulator clear. The SVA reset property catches the stale
accumulator before it can silently corrupt later results.

## Part B: SVA properties

The six properties in `sva/properties.sv` check output stability, inactive-lane
behavior, accumulator reset, output-state validity, command exclusion during a
pending result, and input-ready state validity. Their intent and failure modes
are explained in `sva/PROPERTY_RATIONALE.md`.

`sva/testbench_sva.sv` runs these checks against the handwritten design.
`sva/testbench_anvil_sva.sv` adapts the same safety intents to the Anvil
request/response interface.

## Part C: Anvil implementation

`anvil/dot_product.anvil` is a sequential one-lane implementation using Anvil
dynamic channels. The compiler-generated artifact is
`anvil/generated/dot_product_anvil.sv`; it is regenerated rather than edited by
hand. The source widens each 8-bit operand to 20 bits before multiplication so
the generated product fits the accumulator arithmetic.

The standalone Anvil test is `tests/tb_dot_product_anvil.sv`.

## Matched differential verification

`sva/testbench_equivalence.sv` drives both implementations with the same
logical transactions through separate protocol adapters. It verifies command
and element handshakes, command length/tag, ordered elements, expected result
values, result tags, multiple commands, partial groups, zero operands,
maximum operands, and output backpressure. It compares transactions rather
than requiring cycle-by-cycle equivalence because the architectures have
different latency and internal state.

The verified test vectors cover lengths 1, 2, 3, and 4. The correct pair of
designs previously produced:

```text
length 1: 63
length 2 with zero operands: 0
length 3: 32
length 4: 70
multiple commands: 30, 50
maximum operands with backpressure: 260100
PASS: matched stimulus, both property suites, and differential comparison passed.
```

## Anvil observations

Three required observations are included:

- `observations/rejected_by_anvil.md` — a timing-unsafe message-lifetime
  example rejected by Anvil with `Value does not live long enough in send!`.
- `observations/accepted_but_wrong.md` — a timing-correct source that replaces
  `*accum + prod` with `*accum + p_a`; Anvil accepts it, but differential
  simulation detects the wrong result.
- `observations/compiler_trace.md` — source-to-compiler-pass-to-generated-SV
  trace for `p_a * p_b`, based on compiler revision
  `d138cabedbfc3b65c08249ce6a55cb90dad959da`.

## Reproduction commands

From `D:\anvil`:

```text
dune exec anvil -- -just-check D:\anvil-vector-dot-product\anvil\dot_product.anvil
dune exec anvil -- -just-check D:\anvil-vector-dot-product\anvil\dot_product_drop_product.anvil
dune exec anvil -- -just-check D:\anvil-vector-dot-product\anvil\dot_product_rejected.anvil
```

Expected exit codes are `0`, `0`, and `1`, respectively. The first two are
accepted; the third is rejected by the lifetime checker.

In EDA Playground, compile the correct handwritten SV and correct generated SV
with `sva/testbench_equivalence.sv` using Verilator and `--assert`. To run the
negative functional experiment, substitute the generated drop-product SV.

## Conclusion

The repository contains the implementation, property suite, independent
functional tests, matched differential test, compiler trace, and both required
Anvil negative observations. Generated RTL is reproducible from Anvil source,
and the working tree is maintained with the correct and intentionally broken
experiments clearly separated.

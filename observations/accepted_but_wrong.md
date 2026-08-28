# Accepted by Anvil, but functionally wrong

This observation uses the retained negative-control source
`anvil/dot_product_drop_product.anvil`. It preserves the same channel
contracts and sequencing as the correct design, but changes one datapath line:

```anvil
// Correct: set accum := *accum + prod >>
set accum := *accum + p_a >>
```

The source therefore remains syntactically, type, and timing valid while
computing `A` instead of `A*B`.

## Anvil check and generation

Command:

```text
dune exec anvil -- -just-check D:\anvil-vector-dot-product\anvil\dot_product_drop_product.anvil
```

Observed result: exit code `0`, with no diagnostics. The source was accepted
by Anvil's checks.

Generation command:

```text
dune exec anvil -- D:\anvil-vector-dot-product\anvil\dot_product_drop_product.anvil > D:\anvil-vector-dot-product\anvil\generated\dot_product_drop_product_anvil.sv
```

The generated RTL contains the corresponding mutation:

```systemverilog
assign thread_0_wire$40 = thread_0_wire$39 + thread_0_wire$29;
```

## Functional evidence

Using the matched differential testbench with the correct handwritten SV and
this wrong generated Anvil SV:

```text
=== TEST 1: length 1 ===
Anvil result mismatch: got 9/tag1 expected 63/tag1
Exit code expected: 0, received: 1
```

The failure is intentional: for the first vector, the expected dot product is
`63`, but the mutated datapath produces `9` in the recorded run. The protocol
still reaches the result, proving this is a functional error rather than a
timing failure.

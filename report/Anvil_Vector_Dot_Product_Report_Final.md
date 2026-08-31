# Exploratory Anvil Project — Vector Dot-Product Accelerator

**Intikhab Khursheed | 28 August 2026**

---

## 1. Project Objective and Design

This project investigates how much timing safety can be obtained from Anvil's type system compared with a handwritten SystemVerilog design plus a manually written SVA specification. The required workflow was to build a working accelerator in SystemVerilog, specify its important safety properties, reimplement the design in Anvil, and compare both implementations under matched transactions.

The chosen accelerator computes a dot product over configurable vectors using 8-bit unsigned elements. The handwritten implementation uses four arithmetic lanes operating in parallel, a shared multi-cycle accumulator, a lane-valid mask for partial groups, and ready/valid backpressure on the input and output. The Anvil implementation intentionally uses a sequential microarchitecture: one element pair is received, multiplied, accumulated, and acknowledged before the next element is accepted. This makes the comparison useful because the designs are functionally equivalent at the transaction boundary while having different internal timing and control structures.

---

## 2. SystemVerilog Reference (Part A)

The reference RTL is `systemverilog/dot_product.sv`. It moves through IDLE, LOAD, REDUCE, and OUTPUT states. Commands carry `cmd_length` and `cmd_tag`; element pairs are accepted during LOAD; the four lane products are generated concurrently using a `generate` loop; REDUCE visits each active lane product over multiple cycles using a shared accumulator; and OUTPUT holds the result stable until the downstream consumer accepts it via the ready/valid handshake. The lane-valid array prevents unused lanes in a partial final group from contributing to the accumulator.

The implementation exercises the exact combination requested by the assignment: concurrent arithmetic lanes, a shared reduction resource visited over multiple cycles, configurable vector length including partial final groups, and input/output backpressure.

The reference testbench `systemverilog/testbench.sv` provides the functional baseline across four scenarios including a partial group, back-to-back commands, and a sustained backpressure stall. A separate broken variant `systemverilog/dot_product_broken.sv` removes the accumulator reset at the command-accept boundary; that defect is used in Part B to demonstrate a property violation.

---

## 3. SVA Specification (Part B)

The project defines six executable properties in `sva/properties.sv`, with written rationale for each in `sva/PROPERTY_RATIONALE.md`. Together they cover interface stability, partial-group correctness, accumulator initialization, output-state ownership, transaction exclusion, and input-state correctness.

| Property | What it protects | Observed role |
|---|---|---|
| P1 | Result and tag remain stable while output is stalled. | Protects interface stability under backpressure. |
| P2 | An inactive lane cannot change the accumulator. | Protects partial-group correctness. |
| P3 | The accumulator is cleared when a command is accepted. | Catches the deliberately broken reset design. |
| P4 | `out_valid` is asserted only in OUTPUT state. | Protects result-state ownership. |
| P5 | A pending result prevents a new command from being accepted. | Prevents transaction overlap and state corruption. |
| P6 | Input is accepted only in LOAD state. | Prevents stray writes to lane storage. |

The broken SystemVerilog design demonstrates the role of P3 concretely. Removing the command-time accumulator clear causes the next computation to inherit the previous result. P3 detects the violation at the cycle immediately following command acceptance, before any incorrect output can propagate further.

`sva/testbench_sva.sv` runs these six properties against the handwritten SV design throughout all functional tests. `sva/testbench_anvil_sva.sv` adapts the corresponding safety intents to the Anvil-generated request/response interface — P2 is replaced by an equivalent count-guard property because the sequential Anvil design has no inactive-lane concept.

---

## 4. Anvil Reimplementation and Generated RTL (Part C)

The Anvil source is `anvil/dot_product.anvil`. It defines structured messages for commands, element pairs, and tagged results, then communicates through three typed channels. The process stores the accumulator, remaining element count, saved tag, and a small state value in registers. The central loop receives one element pair, widens the operands, multiplies them, adds the product to the accumulator, decrements the remaining count, and acknowledges the element before accepting the next.

The Anvil design is intentionally sequential rather than a port of the four-lane structure. One element is processed per loop iteration. The two designs are therefore functionally equivalent at the transaction boundary while having different internal timing, which makes the comparison at that boundary the technically meaningful one.

A significant implementation detail was arithmetic width. The Anvil compiler represents a binary multiplication wire at the maximum operand width. With raw 8-bit operands the product wire would be 8 bits, which is insufficient for values up to 65025. The source therefore explicitly constructs 20-bit operands before multiplication using equal-width 4-bit chunk concatenations:

```anvil
let p_a = #{4'd0, 4'd0, 4'd0, pair.a[4+:4], pair.a[0+:4]} >>
let p_b = #{4'd0, 4'd0, 4'd0, pair.b[4+:4], pair.b[0+:4]} >>
let prod = p_a * p_b >>
```

This explicit widening was necessary after earlier attempts using raw 8-bit operands did not preserve the desired product range in the generated RTL. The 20-bit operands match the 20-bit accumulator contract used throughout the project.

The generated artifact is `anvil/generated/dot_product_anvil.sv`, produced by the compiler at the recorded revision and not edited manually. The generated RTL contains the corresponding multiplication and accumulation as continuous assignments:

```systemverilog
assign thread_0_wire$38 = thread_0_wire$29 * thread_0_wire$37;
assign thread_0_wire$40 = thread_0_wire$39 + thread_0_wire$38;
```

The surrounding generated event logic controls when these values may update state or be presented at the output channel.

---

## 5. Matched-Stimulus Differential Testing

The differential testbench is `sva/testbench_equivalence.sv`. It uses one logical transaction source fanned out through two protocol adapters: a ready/valid adapter for the handwritten SV implementation and a channel-handshake adapter for the Anvil-generated interface. Both property suites run simultaneously throughout the simulation.

Because the two architectures have different timing and native protocols, the comparison is intentionally transaction-level rather than cycle-for-cycle. For every transaction, the testbench sends the same command and ordered element sequence to both DUTs, verifies the required handshake counts on both sides, checks each result independently against the mathematical expectation, and then compares the observed results and tags.

The suite was executed in Verilator 5.044 through EDA Playground. All seven cases passed with no assertion failures:

| Case | Condition | Expected | Result |
|---|---|---:|---|
| 1 | Length 1 | 63 | SV=63, Anvil=63 — PASS |
| 2 | Length 2, zero operands | 0 | SV=0, Anvil=0 — PASS |
| 3 | Length 3, partial group | 32 | SV=32, Anvil=32 — PASS |
| 4 | Length 4 | 70 | SV=70, Anvil=70 — PASS |
| 5A | Multiple commands | 30 | SV=30, Anvil=30 — PASS |
| 5B | Multiple commands | 50 | SV=50, Anvil=50 — PASS |
| 6 | Max operands + backpressure | 260100 | SV=260100, Anvil=260100 — PASS |

The comparison intentionally does not require internal accumulator or lane-state equality across the two architectures, because those states have different representations and update timing. Implementation-specific properties check the corresponding safety invariants within each design, while cross-implementation equivalence is established at the observable transaction boundary. This is the meaningful comparison point for two intentionally different microarchitectures.

---

## 6. What Anvil Accepts and What It Does Not Guarantee

The most important result of the project is the demonstrated separation between timing safety and functional correctness. Anvil's compiler checks timing and lifetime discipline, but a program that passes those checks is not guaranteed to implement the intended arithmetic.

### 6.1 Anvil rejects a timing/lifetime violation

`anvil/dot_product_rejected.anvil` is a minimal request/response design that attempts to send a received value after its guaranteed lifetime has ended. Before running the compiler, the predicted failure was a borrow/lifetime error on the `send` statement.

```text
dune exec anvil -- -just-check anvil/dot_product_rejected.anvil
```

The compiler produced exactly the predicted diagnostic and exited with code 1:

```text
Compilation failed!
Borrow checking failed:
Value does not live long enough in send!
anvil\dot_product_rejected.anvil:13:9
```

No unrelated warnings were present. Anvil therefore rejected the design during its lifetime checking phase, before any SystemVerilog could be generated. This is the first required observation: a plausible design is stopped at compile time because the timing/lifetime obligation of a channel send cannot be satisfied.

### 6.2 Anvil accepts a timing-safe but functionally wrong design

`anvil/dot_product_drop_product.anvil` preserves the normal channel structure, sequencing, and lifetime discipline of the correct design but changes one datapath line: it accumulates the first operand `p_a` instead of the computed product `prod`.

```anvil
// Correct:   set accum := *accum + prod >>
// Mutated:   set accum := *accum + p_a  >>
```

Anvil accepted this source with `-just-check` and exit code 0 — `p_a` is a valid, live value at that point, so no timing or lifetime rule is violated. The generated RTL contains the corresponding wrong arithmetic. When run through the matched differential testbench, the mutated implementation produced 9 for the length-1 vector while the correct dot product is 63. The protocol completed normally; the failure is purely semantic.

This experiment answers the central research question directly. Anvil provides a strong compile-time guarantee for timing and lifetime safety. Functional intent — whether the arithmetic computes the right answer — remains the responsibility of the designer and must be verified through assertions, reference models, or differential testing.

---

## 7. Compiler Trace: From Anvil Source to SystemVerilog

Compiler revision: `d138cabedbfc3b65c08249ce6a55cb90dad959da`

Traced construct: `let prod = p_a * p_b >>`

```
anvil/dot_product.anvil
    ↓  lib/compileDriver.ml       — parses source, drives graph build, invokes codegen
    ↓  lib/graphBuilder.ml        — Binop(Mul): builds operand wires, calls add_binary
    ↓  lib/wireCollection.ml      — stores Binary(Mul, w1, w2); width = max(20,20) = 20 bits
    ↓  lib/codegen.ml             — pattern-matches Binary, emits formatted SV assignment
    ↓  anvil/generated/dot_product_anvil.sv
```

`compileDriver.ml` parses the source files, builds the event-graph collections, and calls `Codegen.generate` unless `-just-check` is requested. In `graphBuilder.ml`, the `Binop` case recursively constructs both operand wires and calls `WireCollection.add_binary` with the `Mul` tag. `wireCollection.ml` stores the operation as a `Binary` wire source and sets the wire width to the maximum of the two operand widths — 20 bits in this design, because both `p_a` and `p_b` are 20-bit values. Finally, `codegen.ml` pattern-matches the `Binary(Mul, ...)` node and emits the formatted SystemVerilog operator.

The resulting generated assignment is:

```systemverilog
assign thread_0_wire$29 = {thread_0_wire$22, thread_0_wire$23,
                            thread_0_wire$24, thread_0_wire$26, thread_0_wire$28}; // p_a
assign thread_0_wire$37 = {thread_0_wire$30, thread_0_wire$31,
                            thread_0_wire$32, thread_0_wire$34, thread_0_wire$36}; // p_b
assign thread_0_wire$38 = thread_0_wire$29 * thread_0_wire$37;                    // prod
assign thread_0_wire$40 = thread_0_wire$39 + thread_0_wire$38;                    // accum
```

This trace demonstrates a concrete, non-trivial path from Anvil source syntax through the intermediate wire representation to the final generated RTL, rather than treating the compiler output as a black box.

---

## 8. Findings and Assignment Completion

| Assignment requirement | Evidence in repository | Status |
|---|---|---|
| A. Working SystemVerilog design | `systemverilog/dot_product.sv` + functional testbench | Complete |
| A. Concurrent activity, backpressure, partial groups exercised | `testbench.sv` Tests 3, 4, and backpressure stall | Complete |
| B. SVA specification + rationale | `sva/properties.sv` + `PROPERTY_RATIONALE.md` | Complete |
| B. Broken design caught by a property | `dot_product_broken.sv`; P3 detects missing reset | Complete |
| C. Anvil port + generated RTL | `anvil/dot_product.anvil` + generated RTL | Complete |
| C. Matched stimulus / differential test | `testbench_equivalence.sv`; seven cases passed | Complete |
| Observation 1: rejected by Anvil | `observations/rejected_by_anvil.md` | Complete |
| Observation 2: accepted but wrong | `observations/accepted_but_wrong.md` | Complete |
| Observation 3: compiler trace | `observations/compiler_trace.md` | Complete |
| README + repository structure | `README.md` | Complete |

The key finding is that Anvil removes a class of timing and lifetime mistakes from the manual verification burden, but it does not replace functional specification. The two responsibilities are complementary rather than competing.

---

## 9. Conclusion

The main result of this project is the demonstrated separation of responsibilities between Anvil's compile-time timing guarantee and conventional functional verification. SystemVerilog plus SVA provides explicit functional and protocol specifications that can be checked against any stimulus. Anvil moves an important class of timing and lifetime errors into compile time, so they are caught before RTL generation regardless of test coverage.

The rejected example shows this guarantee in practice: a value-lifetime violation is detected at compile time and no RTL is produced. The accepted-but-wrong example shows the boundary of that guarantee: a design can satisfy every lifetime and timing rule while computing the wrong answer. Functional tests and SVA-derived verification remain necessary at that boundary.

The matched differential test bridges the two implementations independently of their microarchitectural differences. It verifies the requested handshakes, checks each result against the mathematical expectation, and compares the two observable results and tags at the transaction boundary. Because the designs are intentionally different internally, transaction-level equivalence is more meaningful than requiring identical cycles or identical internal state.

---

## 10. What I Would Improve in Anvil

**Arithmetic width inference.** Multiplication required several iterations before arriving at the final equal-width concatenation. Clearer diagnostics and a simpler explicit widening syntax — analogous to `zero_extend` in other HDLs — would reduce this friction significantly.

**Separated diagnostics.** Timing/lifetime errors and type-width errors currently appear in similar formats. Visually separating them would make it easier to identify the primary cause of a compilation failure immediately.

**Readable compiler mapping.** The source-to-event-graph-to-generated-RTL path is traceable, but requires following several OCaml modules. A human-readable intermediate representation or source-annotated output would make the compiler's reasoning more accessible to users who want to understand or trust the generated RTL.

**Functional verification story.** Anvil can guarantee timing safety, but the project demonstrates that arithmetic correctness is an independent property. A first-class workflow for pairing Anvil's type guarantees with functional assertions or reference models — even informally documented — would complete the verification picture that this project had to construct manually.

---

## 11. Reproducibility and Artifacts

```
anvil-vector-dot-product/
├── systemverilog/    — dot_product.sv, dot_product_broken.sv, testbench.sv
├── sva/              — properties.sv, PROPERTY_RATIONALE.md,
│                       testbench_sva.sv, testbench_anvil_sva.sv,
│                       testbench_equivalence.sv
├── anvil/            — dot_product.anvil, dot_product_rejected.anvil,
│                       dot_product_drop_product.anvil,
│                       generated/dot_product_anvil.sv,
│                       generated/dot_product_drop_product_anvil.sv
├── tests/            — tb_dot_product_anvil.sv
├── observations/     — rejected_by_anvil.md, accepted_but_wrong.md,
│                       compiler_trace.md
└── README.md
```

Anvil compiler revision used: `d138cabedbfc3b65c08249ce6a55cb90dad959da` (recorded in `observations/compiler_trace.md`).

Simulation tool: Verilator 5.044 via EDA Playground with `--assert`.

The final evidence set consists of source implementations, executable SVA properties, compiler-generated RTL, intentionally broken designs, actual compiler diagnostics, and matched differential simulation results. Together these directly address the investigation question: **Anvil removes an important class of timing and lifetime hazards from the manual verification burden, while functional correctness remains an independent obligation that requires explicit specification and testing.**

---

## References

1. Exploratory Anvil Project brief, *A Vector or Dot-Product Accelerator in Anvil*, supplied by Dr. Umang Mathur.
2. Anvil compiler source, revision `d138cabedbfc3b65c08249ce6a55cb90dad959da` — `compileDriver.ml`, `graphBuilder.ml`, `wireCollection.ml`, `codegen.ml`.
3. Project repository: https://github.com/IntikhabKhursheed/anvil-vector-dot-product

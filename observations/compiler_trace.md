# Compiler trace: Anvil multiplication

Compiler revision inspected: `d138cabedbfc3b65c08249ce6a55cb90dad959da` in
`D:\anvil`.

This trace follows the non-trivial multiplication used by this project:

```anvil
let prod = p_a * p_b >>
```

## 1. Anvil source

In [`anvil/dot_product.anvil`](../anvil/dot_product.anvil), `pair.a` and
`pair.b` are 8-bit fields.  The source first constructs `p_a` and `p_b` as
20-bit values from five 4-bit chunks (three zero chunks plus the two nibbles
of the original byte):

```anvil
let p_a = #{4'd0, 4'd0, 4'd0, pair.a[4+:4], pair.a[0+:4]} >>
let p_b = #{4'd0, 4'd0, 4'd0, pair.b[4+:4], pair.b[0+:4]} >>
let prod = p_a * p_b >>
```

The explicit widening is required because this compiler's generated wire
arithmetic is width-limited. Earlier versions used 8-bit operands (or
unsupported casts/zero-extension forms), which lost upper product bits. The
final equal-width concatenation is the working version and keeps the generated
operands and accumulator arithmetic at 20 bits.

## 2. `lib/compileDriver.ml`

`compile` parses source files, schedules concrete processes, and calls
`GraphBuildDriver.build` at lines 61–63.  After graph construction, lines
107–112 call `Codegen.generate` unless `-just-check` was requested.  Thus this
pass is the source-to-IR/code-generation driver, not a hand-written RTL path.

## 3. `lib/graphBuilder.ml`

`construct_graphIR` handles an AST `Binop` at lines 166–198.  For the `Mul`
expression it recursively builds the two operands, then calls
`WireCollection.add_binary ... binop ...` (lines 183–187).  The operands are
therefore represented as wires and the operation is retained as a `Mul`
binary node in the event graph.

## 4. `lib/wireCollection.ml`

`Wire.new_binary` (lines 45–77) stores
`source = Binary (binop, w1, w2)`.  For `Mul`, the wire size is the maximum of
the operand sizes in this compiler (line 50–54).  Because both operands in
this design are 20 bits, the product wire is 20 bits and is suitable for the
20-bit accumulator.

This is a width observation about the generated wire, not a claim that the
compiler automatically produces a 40-bit result. The current source widens
both operands to 20 bits before multiplication, and the generated `$38` wire
is correspondingly 20 bits.

## 5. `lib/codegen.ml`

`codegen_wire_assignment` (lines 156–255) pattern-matches a
`WireCollection.Binary`.  Its `Binary (binop, ...)` case (lines 193–209)
formats the two wire names and `Format.format_binop binop`; line 255 emits
the resulting expression as an SV continuous assignment.  The surrounding
`codegen_post_declare` pass (lines 258–265) declares wires and emits these
assignments in dependency order.

## 6. Generated SystemVerilog

The generated file
[`anvil/generated/dot_product_anvil.sv`](../anvil/generated/dot_product_anvil.sv)
contains the concrete result at lines 101–104:

```systemverilog
assign thread_0_wire$29 = {thread_0_wire$22, thread_0_wire$23,
                           thread_0_wire$24, thread_0_wire$26,
                           thread_0_wire$28};
assign thread_0_wire$37 = {thread_0_wire$30, thread_0_wire$31,
                           thread_0_wire$32, thread_0_wire$34,
                           thread_0_wire$36};
assign thread_0_wire$38 = thread_0_wire$29 * thread_0_wire$37;
assign thread_0_wire$40 = thread_0_wire$39 + thread_0_wire$38;
```

`thread_0_wire$29` and `$37` are the widened 20-bit `p_a` and `p_b`; `$38` is
the multiplication result and `$40` feeds the accumulator update.  This is
the direct compiler-generated form of the source `p_a * p_b` expression.

# SVA Property Rationale
## Vector Dot-Product Accelerator

This document explains why each SVA property was chosen, what specific bug it
prevents, and how a violation would appear during simulation.

---

### Property 1: Output Stability Under Backpressure

Once the chip asserts out_valid to signal that a result is ready, the result
and tag values must remain unchanged until the downstream consumer accepts them
by asserting out_ready. The chip stays in OUTPUT state during this wait, and
nothing in that state should modify result_q or tag_out_q.

Without this property, a design bug could overwrite the result register before
the caller reads it. The caller might read a partially updated value or the
wrong result entirely. This is especially dangerous when out_ready is held low
for several cycles, which is a normal and expected condition in any system with
backpressure.

Backpressure is a normal operating condition in any ready/valid system, not a
rare edge case. The design must handle any number of wait cycles correctly.

A violation appears as result or out_tag changing value during a cycle where
out_valid is high and out_ready is low. In simulation, the assertion fires
immediately on the cycle where the change occurs.

---

### Property 2: Inactive Lanes Must Not Affect the Accumulator

When a vector length is not a multiple of LANES, the final group of lanes is
partially filled. Lanes that received no element have their lane_valid_q flag
set to 0. During the REDUCE phase, only lanes with valid data should contribute
to the accumulator. An inactive lane still has a lane_prod value computed from
whatever garbage data sits in the uninitialized lane registers, so it must be
explicitly skipped.

Without this property, an inactive lane's product would silently add to the
accumulator. In Test 2 with length 3, lane 3 is empty. If that lane were not
skipped, the result would exceed 32 by an arbitrary amount depending on what
happens to be in lane_a_q[3] and lane_b_q[3].

A violation appears as accum_q changing on a cycle where the lane being
processed has lane_valid_q equal to 0. This means garbage data entered the
final sum without detection.

---

### Property 3: Accumulator Resets on Every New Command

When a new command is accepted, the accumulator must be cleared to zero before
the new computation begins. This ensures that each dot-product result is
computed from a clean starting point and does not inherit anything from the
previous operation.

This property directly catches the bug in dot_product_broken.sv. That version
removes the reset line, so the accumulator carries its final value from one
command into the next. The effect compounds across commands. Test 1 ends with
accum_q at 70. When Test 2 starts, the accumulator is still 70, so the result
becomes 102 instead of 32. Each subsequent test makes the error worse.

In the simulation of the broken design, Test 1 ends with accum_q at 70. When
Test 2 starts, the accumulator still holds 70, so the result becomes 102
instead of the correct 32. Each subsequent command compounds the error further.

Property 3 fires at the cycle immediately after the command handshake, checking
that accum_q is zero. On the broken design, it fails at exactly that point,
reporting the error before any wrong computation can propagate further.

---

### Property 4: out_valid Is Only Asserted in OUTPUT State

The out_valid signal tells the downstream system that a result is ready to be
collected. It should only be high when the chip is actually in the OUTPUT state.
In any other state, asserting out_valid would be a false signal that causes the
caller to read data that is not yet stable or has not been computed at all.

Without this property, a state machine bug that prematurely asserts out_valid
would cause the caller to latch an incorrect value. This type of bug is hard to
catch in a testbench because the timing glitch may only appear under specific
input sequences.

A violation appears as out_valid being high during IDLE, LOAD, or REDUCE state.
Since out_valid is driven directly by a state comparison, this would indicate
the state encoding or the output assignment logic is wrong.

---

### Property 5: No New Command Accepted While Result Is Pending

While the chip is in OUTPUT state delivering a result, cmd_ready must be low.
The chip cannot simultaneously accept a new command and deliver the current
result because accepting a new command immediately resets length_q, tag_q, and
accum_q. If that happened while out_valid is still high, the tag delivered to
the caller would belong to the old command but the internal state would already
belong to the new one.

Without this property, a design that incorrectly raises cmd_ready during OUTPUT
would allow a race condition where a new command corrupts the state before the
old result is safely handed off.

If cmd_ready were high during OUTPUT, a new command would immediately overwrite
tag_q before the old result is read. The caller would see out_tag from the old
command alongside a result that already belongs to the new command, a complete
mismatch that is silent and difficult to debug.

A violation appears as cmd_ready and out_valid both being high in the same
cycle, which is a clear protocol violation.

---

### Property 6: in_ready Is Only Asserted in LOAD State

The in_ready signal tells the input stream that the chip can accept an element
pair. This should only be true when the chip is in LOAD state. Accepting an
element during REDUCE would write into lane registers that are currently being
read by the accumulator logic. Accepting an element during OUTPUT or IDLE would
write into registers with fill_q in an undefined position relative to the
current command.

Without this property, a state machine glitch that leaves in_ready high outside
of LOAD would allow stray elements to enter the lane registers at the wrong
time. The computation would silently use wrong data and produce a wrong result
with no visible error signal.

A violation appears as in_ready being high during any state other than LOAD.
Since in_ready is driven directly by the state comparison, this indicates a
problem in the output assignment logic.

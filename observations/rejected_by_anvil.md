# Rejected by Anvil: timing-unsafe design

`anvil/dot_product_rejected.anvil` is a small, plausible request/response
design that violates a message lifetime contract. `read_resp` promises data
tied to `read_req`, but the process sends the received `addr` directly. That
value is not guaranteed to remain live for the response timing.

## Prediction

Anvil's lifetime checker should reject the source with a borrow/lifetime error
before generating SystemVerilog.

## Command

```text
dune exec anvil -- -just-check D:\anvil-vector-dot-product\anvil\dot_product_rejected.anvil
```

## Actual diagnostic

```text
Compilation failed!
Borrow checking failed:
Value does not live long enough in send!
anvil\dot_product_rejected.anvil:13:9:
     13|         send endp.read_resp(addr) >>
        |         ^^^^^^^^^^^^^^^^^^^^^^^^^
```

The command exited with code `1`. Anvil therefore rejected this design during
its timing/lifetime pass, exactly as predicted. This minimal variant produces
no warnings; the rejection is the lifetime error itself.

The working design in `anvil/dot_product.anvil` avoids this class of violation
by using dynamic request/response handshakes and values whose lifetimes are
managed by the sequential protocol.

# Provenance

## Reused or referenced
- Anvil compiler (commit `d138cabedbfc3b65c08249ce6a55cb90dad959da`), its documentation, and the Anvil paper (arXiv:2503.19447).
- The RISC-V Vector Extension, Ara and Snitch references from the brief were read for ideas. No code was copied from them.

## AI assistance
- **Anvil syntax:** Anvil is a new language, so I used an AI assistant to help with its syntax while writing the Anvil port. I understood the control flow and design (how the sequential design works) and checked every result by simulation.

- **anvil/dot_product.anvil**, **dot_product_drop_product.anvil** and **dot_product_rejected.anvil**: Anvil syntax help.
report/: wording polish.

- **Report:** I used an AI assistant to polish the wording of the report and to ask for suggestions. The content and conclusions are mine.
- **Tooling:** AI also helped with file-encoding and run-script fixes (converting the generated Anvil `.sv` files from UTF-16 to UTF-8, and `run_all.sh`).

## Done by me
The architecture, the SystemVerilog design, the six SVA properties and the rationale for each, the three Anvil observations, and the conclusions.

## Verification
All runs were checked in Verilator (EDA Playground 5.044, and `run_all.sh` on Verilator 5.020). Results are in `results/SIMULATION_RESULTS.md`.

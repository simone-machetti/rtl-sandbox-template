# Log

Change history for the Example wiki — newest first. Entries are grouped by ISO-8601 date, each line `**[Action]**: description`.

## 2026-09-16

- **[Update]**: [Example Top](architectures/top_example.md) — the hierarchical run now fixes the boundary pins: `pins_mac_n.tcl` for the hardened `mac_n` (operands on the left and top edges, result on the right) and `pins_top_example.tcl` for the wrapper on the same edges, and the block is hardened with its routing capped at M5 and the tile PDN. The project README's walkthrough carries the commands and the refreshed reference results.

## 2026-09-14

- **[Creation]**: Wiki scaffold for the template's reference project: [index.md](index.md), this log, and the `architectures/`, `modules/`, `testbenches/` folders.
- **[Creation]**: [Example Top](architectures/top_example.md) — `top_example`, the registered flow-validation vehicle: `reg_n` input registers (operands and signedness flags), one `mac_n` core, `reg_n` output register; 2-cycle latency; `LANES` / `WIDTH_A` / `WIDTH_B` overridable through the flow's `PARAMS`.
- **[Creation]**: Module pages for the datapath — [mac_n](modules/mac_n.md) (multi-lane multiply-accumulate, the hard-macro candidate), [mul_n](modules/mul_n.md) (runtime-signedness multiplier, one extra product bit so unsigned × unsigned stays non-negative), [add_tree_n](modules/add_tree_n.md) (heap-ordered balanced tree of `add_n` nodes at the final width, so no node can overflow), [add_n](modules/add_n.md) (modular two-input adder) and [reg_n](modules/reg_n.md) (register bank).
- **[Creation]**: Testbench pages — [tb_top_example](testbenches/tb_top_example.md) (streaming, one-iteration delayed golden, `POST_SYN_SIM` flat-port branch) and [tb_mac_n](testbenches/tb_mac_n.md) (combinational, all four signedness combinations per vector). Both pass with 0 mismatches at the default shape and `tb_top_example` also at `LANES=8 WIDTH_B=4`.

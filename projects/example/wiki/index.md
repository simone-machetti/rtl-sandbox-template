# Example Wiki

Design documentation for the **example** project — the flow-validation design shipped with the template. Each page summarizes and cross-references the project's own `rtl/` and `tb/` sources and links back to them. See [log.md](log.md) for the change history.

> Organized as: **architectures/** — the top-level assemblies (`top_example`); **modules/** — the reusable building blocks (the `mac_n` core, its `mul_n` / `add_tree_n` / `add_n` datapath primitives, and the `reg_n` register bank); **testbenches/** — the self-checking testbenches (`tb_<module>`); plus `concepts/`, `decisions/`, `experiments/`, `references/`, empty until the project grows.

## Architectures

* [Example Top](architectures/top_example.md) — `top_example`: one `mac_n` core between `reg_n` input and output registers; a single reg-to-reg pipeline stage, 2-cycle latency, parameterized shape (default 4 lanes of 8 × 8 bits).

## Modules

* [Multiply-Accumulate N](modules/mac_n.md) — `mac_n`: `LANES` parallel `mul_n` products accumulated by one `add_tree_n` into an exact `WIDTH_A + WIDTH_B + 1 + ceil(log2(LANES))`-bit result; runtime signedness per operand; combinational. The block hardened as a macro in the hierarchical run.
* [Multiplier N](modules/mul_n.md) — `mul_n`: `WIDTH_A × WIDTH_B` multiplier with runtime signedness per operand, exact `WIDTH_A + WIDTH_B + 1`-bit product.
* [Adder Tree N](modules/add_tree_n.md) — `add_tree_n`: balanced binary tree of `add_n` nodes summing `SIZE` words with `ceil(log2(SIZE))` bits of growth, sign- or zero-extended leaves, heap-ordered storage.
* [Adder N](modules/add_n.md) — `add_n`: two-input modular adder, the tree node.
* [Register N](modules/reg_n.md) — `reg_n`: register bank, `SIZE` `WIDTH`-bit registers, shared asynchronous active-low reset.

## Testbenches

* [tb_top_example](testbenches/tb_top_example.md) — full-throughput streaming check of the registered result against a pipeline-delayed exact golden, random corner-biased operands with random signedness, then directed extremes under all four signedness combinations; `POST_SYN_SIM` branch for gate-level runs.
* [tb_mac_n](testbenches/tb_mac_n.md) — combinational check of `out_o` against the exact sum of products, every vector under all four signedness combinations, random corner-biased plus directed extremes.

## Concepts

_None yet._

## Decisions

_None yet._

## Experiments

_None yet._

## References

_None yet._

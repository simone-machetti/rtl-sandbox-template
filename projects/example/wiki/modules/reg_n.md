# Register N

`reg_n` — Parameterized register-bank primitive: `SIZE` independent `WIDTH`-bit registers with a shared asynchronous active-low reset. [top_example](../architectures/top_example.md) uses it for its input and output pipeline registers.

## Purpose

Holds `SIZE` independent `WIDTH`-bit registers behind one module, so a design's pipeline stages come from a single parameterized source rather than ad-hoc `always_ff` blocks. There is no enable — each register loads every cycle, so any hold or accumulate behavior is provided by upstream logic feeding `d_i`.

## Parameters

| Parameter | Default | Description                      |
| --------- | ------- | -------------------------------- |
| `WIDTH`   | 8       | Bit width of each register.      |
| `SIZE`    | 4       | Number of registers in the bank. |

## Interface

| Signal   | Dir | Width            | Description                                               |
| -------- | --- | ---------------- | --------------------------------------------------------- |
| `clk_i`  | in  | 1                | Clock; registers update on the rising edge.               |
| `rst_ni` | in  | 1                | Asynchronous active-low reset; clears all registers to 0. |
| `d_i`    | in  | `SIZE` × `WIDTH` | Input words — unpacked array `[0:SIZE-1]`.                |
| `q_o`    | out | `SIZE` × `WIDTH` | Registered outputs — unpacked array `[0:SIZE-1]`.         |

## Instantiation

```systemverilog
reg_n #(.WIDTH(8), .SIZE(4)) reg_n_i (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .d_i    (d),
    .q_o    (q)
);
```

## Internal logic

The whole bank is one clocked process. There is no combinational output path — `q_o` is state, driven only inside an `always_ff`.

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        for (int i = 0; i < SIZE; i++) begin
            q_o[i] <= '0;
        end
    end else begin
        for (int i = 0; i < SIZE; i++) begin
            q_o[i] <= d_i[i];
        end
    end
end
```

- **Sensitivity** — the process wakes on the rising edge of `clk_i` and on the falling edge of `rst_ni`; listing `negedge rst_ni` is what makes the reset *asynchronous*: the clear happens the moment `rst_ni` drops, without waiting for a clock edge.
- **Reset branch** — while `rst_ni` is low every one of the `SIZE` registers is held at `'0`, the width-agnostic zero literal filling all `WIDTH` bits.
- **Clocked branch** — when `rst_ni` is high each rising edge copies `d_i[i]` into `q_o[i]`; no enable, no feedback, so the bank is a plain set of `SIZE` parallel D flip-flop groups. Non-blocking assignments make all registers sample the *old* inputs simultaneously.
- **Hold and accumulate come from outside** — to keep or accumulate a value, mux `q_o` back into `d_i` or feed it through an adder; the primitive itself stays minimal and reusable.

Source: [reg_n.sv](../../rtl/reg_n.sv)

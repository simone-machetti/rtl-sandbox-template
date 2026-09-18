# P&R stage 1 — Floorplan

The floorplan stage turns a netlist — a purely logical object — into a physical canvas: a die with standard-cell rows, routing tracks, I/O pins, well taps, and a power grid, ready for placement. Everything later in place-and-route happens *inside* the frame this stage builds, which is why most P&R quality problems (congestion, IR drop, unroutable pins) trace back to floorplan decisions.

## Inputs and outputs

- **Inputs**: the synthesized netlist (`imp/<NETLIST_DIR>/output/netlist.v`), the ASAP7 technology and standard-cell LEFs, the liberty timing models, the generated constraints — plus, in hierarchical runs, the hardened blocks' abstracts (`MACRO_DIRS`) and the macro-placement file (`FLOORPLAN`).
- **Outputs**: the floorplan checkpoint `output/1_floorplan.odb` and the stage report `report/1_floorplan.rpt`.

After this stage the database contains: the die and core outlines, standard-cell rows, routing tracks, placed I/O pins, tie cells driving the netlist's constant nets, tap and endcap cells, the complete power grid — and every logic cell of the netlist, still unplaced. Stage 2 (placement) starts from this checkpoint.

## Theory

### Die, core, and how big the chip is

The **die** is the full silicon rectangle. The **core** is the inner region where standard cells may be placed; the ring between core and die edge (the *core margin*) is kept free for the I/O pins' metal and, in chip-level flows, for the pad ring. Two ways exist to size them:

- **Utilization-driven** (this flow): you state what fraction of the core area the cells should occupy, and the tool computes the die from the netlist's total cell area. For instance, 4 000 µm² of cells at 40 % utilization yields a 10 000 µm² core — 100 × 100 µm at aspect ratio 1.0.
- **Fixed-die**: you state the outline explicitly (`-die_area`/`-core_area`) and utilization becomes a *result*. Used when the outline is imposed — a chip with a pad ring, a tile that must abut neighbors, a fixed package cavity.

**Utilization** is the single most important floorplan number. It cannot approach 100 %: the empty space is not waste but the working room for everything that comes later — buffers and resized cells from timing repair, clock-tree buffers, and above all *routing*: wires need track capacity, and a too-dense design becomes unroutable long before it becomes full. Typical starting points: 40–60 % for routing-heavy logic at advanced nodes, higher for regular datapaths, lower when congestion appears. The flow's default of 40 % is deliberately comfortable; its cost is area and wire length.

### Standard-cell rows and sites

The core is filled with horizontal **rows**, each one cell-height tall. A row is a sequence of **sites** — the atomic placement unit defined in the technology LEF. For ASAP7's `asap7sc7p5t` library the site is 0.054 µm wide × 0.270 µm tall; every standard cell occupies an integer number of sites, and placement means assigning each cell to sites in some row. "7.5-track" names the row height: 0.270 µm equals 7.5 routing tracks of the 0.036 µm M2 pitch — the taller the cell library (9T, 12T), the more room for wide transistors (faster, larger); shorter libraries (6T, 7.5T) trade drive strength for density. Rows alternate orientation (N, FS, N, ...) so that neighboring rows share power rails at their common edge. The 100 × 100 µm core above therefore holds about 370 rows of about 1 850 sites each.

### Routing tracks

A **track** is a legal centerline for a wire on a layer: an offset plus a pitch, per direction. The router only uses tracks (plus vias between layers), so track pitch × core size = the total routing capacity of each layer. Tracks are technology data — they must match the width/spacing rules the LEF declares — which is why this flow *sources* them from the platform (`make_tracks.tcl`) rather than inventing them.

### Block pins

For a block-level design the I/O pins are metal rectangles on the core boundary: on layers whose preferred direction is horizontal (M4 in ASAP7) for the left/right edges, vertical layers (M5) for top/bottom. The pin placer distributes the netlist's ports around the boundary, optimizing wire length toward each port's internal loads. Pin geometry matters more than it looks: pins that are too shallow, too clustered, or on too few layers become an access bottleneck for the router — and, in hierarchical flows, for the *parent's* router too.

### Constants need drivers: tie cells

A gate-level netlist contains constant nets (`1'b0`/`1'b1` — unused modes, tied selects). Physically something must *drive* those nets, and wiring a logic input straight to the power grid is illegal twice over: electrically (a gate oxide directly exposed to every supply transient) and methodologically (power is a special net owned by the PDN tool; signal routing is pin-to-pin). **Tie cells** solve both: a TIEHI/TIELO cell outputs a clean constant from a real driver pin, turning each constant into an ordinary routable net.

### Latch-up and well taps

Every CMOS chip contains a parasitic PNPN structure between the PMOS n-wells and the NMOS substrate. If wells and substrate are not firmly held at their supply potentials, injected noise can fire this structure into a self-sustaining VDD→VSS short — **latch-up**. The cure is periodic **well taps**: contacts tying n-well to VDD and substrate to VSS. Classic libraries embed taps in every cell; ASAP7 — like most advanced-node libraries — uses *tapless* cells (denser), so the flow must place dedicated tap cells at a guaranteed maximum spacing. The same cell doubles as the **endcap** terminating each row, guaranteeing well continuity and shielding the outermost cells from lithography edge effects.

### The power distribution network (PDN)

The PDN delivers VDD/VSS to every cell with acceptable **IR drop** (resistive voltage loss — a cell seeing 0.63 V instead of 0.70 V is a slower cell than STA assumed) and acceptable **electromigration** (current density limits on the metal). It is built as a hierarchy:

- **Followpin rails** on M1/M2: thin wires running along every row edge, alternating VDD/VSS, from which cells tap power directly.
- **Straps**: wider wires on upper layers (M5 vertical + M6 horizontal here) forming a mesh that feeds the rails through via stacks. Upper metals are thicker and less resistive — they do the long-distance transport.
- **Rings** (not used in this block-level flow): a thick loop around the core, standard when a pad ring supplies power from the chip edge.

Design currents flow from the top of this hierarchy downward; sizing (strap width, pitch, layer choice) is a tradeoff between IR drop/EM margin and the routing tracks the PDN steals from signals.

### Macros

When the design instantiates hard macros (hardened blocks, SRAMs), the floorplan also fixes their positions, cuts the std-cell rows beneath them, keeps a **halo** (a keep-out margin so std cells don't hug the macro and block its pin access), and gives the PDN a rule for connecting their power pins. This flow's macro mechanics are covered in [18_hierarchical.md](../concepts/hierarchical.md); the walkthrough below shows where they hook in.

## Implementation walkthrough

The stage script is `scripts/pnr/1_floorplan.tcl`, run as an independent `openroad -exit` process by `scripts/pnr/run.sh` ([05_pnr_overview.md](05_pnr_overview.md)).

```tcl
source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl
```

Every stage begins with the three helpers. `init_tech.tcl` loads the five ASAP7 liberty files (timing models must be present before a netlist can be linked) and defines the technology variables used below — this block of it is the one the floorplan consumes:

```tcl
set TECH_LEF        $::env(BEOL_HOME)/lef/asap7_tech_1x_201209.lef
set SC_LEF          $::env(ASAP7_HOME)/lef/asap7sc7p5t_28_R_1x_220121a.lef
set SITE            asap7sc7p5t
set PIN_LAYER_HOR   $::env(SEL_PIN_LAYERS_HOR)
set PIN_LAYER_VER   $::env(SEL_PIN_LAYERS_VER)
set MIN_ROUTE_LAYER M2
set MAX_ROUTE_LAYER $::env(SEL_MAX_ROUTE_LAYER)
set MIN_CLK_LAYER   M4
set TAPCELL         TAPCELL_ASAP7_75t_R
set TIEHI_PORT      TIEHIx1_ASAP7_75t_R/H
set TIELO_PORT      TIELOx1_ASAP7_75t_R/L
```

(`checkpoint.tcl` provides `save_checkpoint`/`load_checkpoint`, `reports.tcl` provides `report_stage`; both are dissected in [05_pnr_overview.md](05_pnr_overview.md).)

```tcl
# -----------------------------------------------------------------------------
# Technology (physical views)
# -----------------------------------------------------------------------------
read_lef $TECH_LEF
read_lef $SC_LEF

if {$::env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $::env(SEL_MACRO_DIRS) {
        read_lef $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$dir/output/abstract.lef
    }
}
```

The **technology LEF** is read first: it defines the layer stack (M1–M9 plus the Pad layer), each layer's preferred direction and design rules, the via definitions, the manufacturing grid, and the `asap7sc7p5t` site — everything else refers to these definitions. The **cell LEF** then provides the physical abstract of all 212 RVT standard cells: footprint in sites, pin shapes and layers, internal obstructions. P&R never sees transistors; it works entirely on these abstracts (the real polygons only appear at the GDS merge, [11_pnr_gds.md](11_pnr_gds.md)). In hierarchical runs, each hardened block's `abstract.lef` is read the same way — from here on a macro is just a very large cell.

```tcl
# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
read_verilog $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_NETLIST_DIR)/output/netlist.v
link_design $::env(SEL_TOP_LEVEL)
```

The synthesized netlist is read (the standard `imp/<NETLIST_DIR>/output/netlist.v` contract) and **linked**: every instance is resolved against the loaded liberty/LEF masters, building the design database. Linking is where names bind — an instantiated module with no Verilog definition resolves to a LEF macro of the same name (the mechanism the hierarchical flow relies on), and an unresolvable reference errors out here, which in this flow almost always means the netlist was not synthesized flat.

```tcl
# -----------------------------------------------------------------------------
# Constraints & wire RC
# -----------------------------------------------------------------------------
source $::env(REPO_HOME)/scripts/pnr/constraints.tcl
source $::env(REPO_HOME)/scripts/pnr/setRC_extra.tcl
source $::env(BEOL_HOME)/setRC.tcl
set_dont_use $DONT_USE
```

Three pieces of *analysis context*, needed even at floorplan time because later stages re-derive everything from checkpoints and this stage's report already includes timing:

- `constraints.tcl` creates the clock and I/O constraints from `CLK_PERIOD_NS` — the full scheme (real clock `clk_i`, virtual clock for I/O, hold false-paths) is the subject of [02_constraints.md](../concepts/constraints.md).
- `setRC.tcl` (platform file) sets per-layer wire resistance/capacitance and the default wire RC used to *estimate* parasitics before routing exists — without it, pre-route timing would assume zero-delay wires. `setRC_extra.tcl`, sourced first, adds estimates for the layers the stock file leaves out (ASAP7: M8, M9, V9, extrapolated from the M4–M7 trend), so a run with `MAX_ROUTE_LAYER=M9` prices its upper wires instead of falling back to the default; a stack whose own file covers those layers overrides them, since it is sourced last.
- `set_dont_use` blacklists cells the optimization engines may not insert or swap to: `{*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}` — fractional-drive cells (poor repair choices), scan flops (no DFT flow), and clock gates (gating is an architectural decision; the ICGs already in the netlist are untouched and fully used). This is an engine restriction, not a netlist filter.

```tcl
# -----------------------------------------------------------------------------
# Floorplan & routing tracks
# -----------------------------------------------------------------------------
initialize_floorplan \
    -utilization  $::env(SEL_CORE_UTIL) \
    -aspect_ratio $::env(SEL_ASPECT_RATIO) \
    -core_space   $::env(SEL_CORE_MARGIN) \
    -site         $SITE
```

The central command. From the linked design's total cell area and the three knobs it computes the core (area = cell area / utilization, shaped by the aspect ratio), adds `-core_space` (2 µm default) on each side to get the die, and fills the core with rows of the `asap7sc7p5t` site. Coordinates snap to legal grid positions — the tool logs it as, e.g., `Core area lower left (2.000, 2.000) snapped to (2.052, 2.160)`: the core corner is aligned to the site and manufacturing grids.

```tcl
source $::env(BEOL_HOME)/openRoad/make_tracks.tcl
```

Track definition, sourced as-is from the platform (it is pure data). Representative lines:

```tcl
make_tracks M7 -x_offset 0.016 -x_pitch 0.064 -y_offset 0.016 -y_pitch 0.064
make_tracks M5 -x_offset 0.012 -x_pitch 0.048 -y_offset 0.012 -y_pitch 0.048
make_tracks M4 -x_offset 0.009 -x_pitch 0.036 -y_offset 0.012 -y_pitch 0.048
make_tracks M2 -x_offset 0.009 -x_pitch 0.036 -y_offset 0.045 -y_pitch 0.270
make_tracks M1 -x_offset 0.009 -x_pitch 0.036 -y_offset 0.009 -y_pitch 0.036
```

Reading M5 as an example: vertical wires may sit at x = 0.012 + k·0.048 — a 0.048 µm pitch, coarser than M2/M3's 0.036 and finer than M7's 0.064; pitch grows up the stack as wires get thicker. M2 is the curiosity: seven `make_tracks M2` lines (only one shown) build an *irregular* horizontal track pattern repeating every 0.270 µm — exactly one row height — because M2 tracks must interleave with the cells' internal M2 geometry and the followpin rails.

```tcl
# -----------------------------------------------------------------------------
# Manual macro placement (project-owned floorplan file)
# -----------------------------------------------------------------------------
if {$::env(SEL_FLOORPLAN) ne "none"} {
    set fp_file $::env(SEL_FLOORPLAN)
    if {[file pathtype $fp_file] ne "absolute"} {
        set fp_file $::env(REPO_HOME)/$fp_file
    }
    source $fp_file
    cut_rows -halo_width_x 1 -halo_width_y 1
}
```

The hierarchical hook: the project-owned `FLOORPLAN` file (one `place_macro -macro_name <inst> -location {x y} -orientation R0` per macro — *the* place where a component's position is decided) is sourced, then `cut_rows` removes the standard-cell rows under each macro and 1 µm of **halo** around it, so no cell can be legalized against the macro's edge and its pin access stays clear. Skipped entirely in flat runs. Details: [Hierarchical flow](../concepts/hierarchical.md); the shipped `example` project hardens `mac_n` inside `top_example` this way (see its README).

```tcl
# -----------------------------------------------------------------------------
# Pin placement (provisional, refined after global placement)
# -----------------------------------------------------------------------------
set_pin_length -hor_length 0.24 -ver_length 0.24
if {$PINS_CFG ne "none"} {
    source $PINS_CFG
}
place_pins -hor_layers $PIN_LAYER_HOR -ver_layers $PIN_LAYER_VER {*}$PIN_ARGS
```

`place_pins` distributes every port on the core boundary: by default M4 shapes on the left/right edges (horizontal-direction layer), M5 on top/bottom (vertical); `PIN_LAYERS_HOR`/`PIN_LAYERS_VER` may name several layers per direction, which doubles the pin slots of an edge (a hardened tile with a 1 000-bit bus on one edge needs it). `set_pin_length` makes each pin a 0.24 µm-deep stub instead of a minimal square — five track-pitches of landing area for whoever routes to it; the value came out of hierarchical bring-up, where macro-pin access proved to be the fragile spot. The optional project file (`PINS`) runs just before: it holds `set_io_pin_constraint` rules that pin each bus to an edge, a span of that edge and an order — the geometry a parent design will route to — and, since it is sourced after the floorplan file, it can read the placed macros to align the boundary pins with them. Two placer facts shape such files: an ordered group is kept only up to the placer's section size (200 slots), larger groups fall back to unconstrained placement, so long buses are split into ordered sub-groups with consecutive spans; and the constraints persist in the ODB, so the placement stage must not source the file again. `PIN_ARGS` passes extra flags (typically a two-track minimum pin distance and a corner avoidance). This placement is *provisional*: ports are placed again after global placement ([07_pnr_place.md](07_pnr_place.md)) once the tool knows where each port's loads actually ended up; doing a first pass now gives the placer sane anchor positions instead of unplaced ports.

```tcl
# -----------------------------------------------------------------------------
# Tie cells & tap cells
# -----------------------------------------------------------------------------
insert_tiecells $TIEHI_PORT -prefix "TIEHI_"
insert_tiecells $TIELO_PORT -prefix "TIELO_"

tapcell -distance 25 -tapcell_master $TAPCELL -endcap_master $TAPCELL
```

`insert_tiecells` finds every constant-1 net and gives it a `TIEHIx1_ASAP7_75t_R` driver (output pin `H`), then the same for constant-0 with TIELO/`L` — one cell per constant net (if one tie ends up driving too many loads, `repair_tie_fanout` in stage 2 clones it). This step exists here because our Yosys flow emits constants as `assign` statements rather than mapping them to tie cells itself (ORFS does it in synthesis via `hilomap` — either point works, but it must happen exactly once).

`tapcell` places the well taps in every row at a maximum 25 µm spacing (the ASAP7 platform's latch-up rule value, staggered row to row), and the same master as endcap at every row end. All of these are *fixed* cells: placement later works around them.

```tcl
# -----------------------------------------------------------------------------
# Power distribution network
# -----------------------------------------------------------------------------
source $PDN_CFG
pdngen
```

`PDN_CFG` is selected in `init_tech.tcl`: the platform's `grid_strategy-M1-M2-M5-M6.tcl` for flat runs, our `scripts/pnr/pdn_macro.tcl` when macros are present, or any file passed via the `PDN` parameter — `scripts/pnr/pdn_tile.tcl` when hardening a block: rails plus a single M5 mesh exposed as M5 power pins, nothing on M6/M7, so the parent can run its own mesh and its routing over the macro. The strategy file only *declares* the grid; `pdngen` builds it. The flat-run strategy, in full:

```tcl
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
global_connect
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}
define_pdn_grid -name {top} -voltage_domains {CORE} -pins {M6}
add_pdn_stripe -grid {top} -layer {M1} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M2} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M5} -width {0.12} -spacing {0.072} -pitch {5.4} -offset {0.300}
add_pdn_stripe -grid {top} -layer {M6} -width {0.288} -spacing {0.096} -pitch {5.4} -offset {0.513}
add_pdn_connect -grid {top} -layers {M1 M2}
add_pdn_connect -grid {top} -layers {M2 M5}
add_pdn_connect -grid {top} -layers {M5 M6}
define_pdn_grid -name {CORE_macro_grid_1} -voltage_domains {CORE} -macro \
  -orient {R0 R180 MX MY} -halo {2.0 2.0 2.0 2.0} -default
add_pdn_connect -grid {CORE_macro_grid_1} -layers {M4 M5}
define_pdn_grid -name {CORE_macro_grid_2} -voltage_domains {CORE} -macro \
  -orient {R90 R270 MXR90 MYR90} -halo {2.0 2.0 2.0 2.0} -default
add_pdn_connect -grid {CORE_macro_grid_2} -layers {M4 M5}
```

Piece by piece: the `add_global_connection` rules declare which *pins* belong to which *power net* by pattern (`VDDPE`/`VDDCE` are SRAM-macro pin names — harmless here); `set_voltage_domain` binds the core to the VDD/VSS pair (one domain — no power gating or multi-voltage in this flow); `define_pdn_grid -pins {M6}` opens the grid `top` and marks M6 as the layer whose straps become the block's *power pins* (where a parent design or a ring would connect). Then the four stripe declarations build the hierarchy from the theory section: 0.018 µm followpin rails on M1 and M2 riding every row edge (pitch 0.54 = two row heights, because VDD and VSS alternate per row), and the strap mesh — 0.12 µm M5 verticals and 0.288 µm M6 horizontals every 5.4 µm (`-spacing` is the VDD-to-VSS gap of each strap *pair*). The `add_pdn_connect` rules tell `pdngen` where to drop via stacks wherever the named layer pairs cross. The two macro grids only matter for designs with SRAM-style macros — and their `M4 M5` connect assumption is exactly what our hardened blocks violate (see Lessons).

```tcl
report_stage 1_floorplan
save_checkpoint 1_floorplan
```

The standard stage epilogue: a timing/area snapshot into `report/1_floorplan.rpt` (WNS here is pre-placement — ideal clocks, estimated wires — useful only as a baseline) and the ODB checkpoint that stage 2 loads.

## Design space

**Utilization vs fixed die.** Utilization-driven floorplans are ideal for exploration — area scales automatically with the netlist. Fixed-die (`initialize_floorplan -die_area {x0 y0 x1 y1} -core_area {...}`) is what you switch to when the outline is a constraint: pad-ring chips, abutted tiles, or a study where two variants must be judged in identical envelopes. The complementary choice for an A-vs-B architecture comparison is keeping *utilization* fixed — then die area itself becomes the measured result.

**Choosing the utilization.** Raising it packs cells tighter: shorter wires (less delay, less dynamic power) but less repair headroom and more routing pressure — detailed-route DRCs and unfixable hold/setup are the classic symptoms of overshooting. Lowering it is the first congestion remedy that needs no skill, at the cost of area and wire length. The productive range at this node is roughly 30–70 %; datapath-regular designs tolerate the high end.

**Aspect ratio** defaults to square, which minimizes average wire length for an unbiased netlist. Elongated cores serve floorplans with directional structure — a pipeline flowing left-to-right, a tile that must match a neighbor's width, pin-heavy designs needing more boundary on two sides.

**Pin placement** has a whole sub-space: more layers per direction (`-hor_layers "M4 M6"`) when pin count outgrows one layer's tracks (designs with tens of thousands of boundary pins need this); `-group_pins` to keep buses contiguous; `-exclude` regions (e.g. `-exclude top:*` to keep a side clean for abutment); `-min_distance` to spread pins; annealing mode for QoR. Chip-level flows replace all of this with a **pad ring** — pre-placed I/O cells with bond pads, wire-bonded or bumped — which ASAP7, having no I/O library, cannot express: one reason this flow is block-level.

**Taps and endcaps.** The 25 µm distance is the platform's rule-of-thumb; real PDKs specify a maximum from the latch-up rule deck — tightening it costs a fraction of a percent of area and buys latch-up margin (aggressive nodes and automotive-grade designs go denser). Libraries with tap-included cells skip the step entirely; some flows use distinct endcap masters with well extensions.

**PDN sizing** is the classic IR-drop-vs-routability dial. Denser/wider straps (smaller `-pitch`, larger `-width`) lower IR drop and EM stress but consume signal tracks on M5/M6 — each 0.12 µm M5 strap pair at 5.4 µm pitch already takes ~5 % of M5's capacity. Real flows close this loop with IR analysis (OpenROAD: `analyze_power_grid`, an experimental static IR solver; commercial: Voltus/RedHawk) and iterate the strategy. Other structural choices: a **core ring** as the interface to a pad ring; straps on M3/M4 for very small blocks; different layer pairs matching where the current actually enters the block. The strategy-file format makes all of this declarative — swapping the `PDN` parameter is enough to experiment.

**Macro floorplanning** (halos, channels between macros, orientation) is deferred to [18_hierarchical.md](../concepts/hierarchical.md); the one principle worth stating here is that *manual* macro placement — our `FLOORPLAN` hook — is the norm, not a limitation: macro positions encode dataflow knowledge (which tile talks to which neighbor) that automatic macro placers only approximate.

## Knobs

| Knob               | Where             | Default   | Effect / tradeoff                                                                      |
| ------------------ | ----------------- | --------- | -------------------------------------------------------------------------------------- |
| `CORE_UTIL`        | make              | 40        | Cell density; ↑ = smaller die, shorter wires ↔ congestion, less repair room            |
| `ASPECT_RATIO`     | make              | 1.0       | Core height/width; square minimizes average wire length                                |
| `CORE_MARGIN`      | make              | 2 µm      | Core-to-die ring; room for boundary pins (and rings, if ever added)                    |
| `FLOORPLAN`        | make              | none      | Macro placement file (hierarchical runs)                                               |
| `MACRO_DIRS`       | make              | none      | Hardened blocks to bind (hierarchical runs)                                            |
| `PDN`              | make              | auto      | PDN strategy file override                                                             |
| pin layers         | make              | M4 / M5   | `PIN_LAYERS_HOR/VER`; more layers = more pin capacity; must match parent-level routing |
| `PINS`             | make              | none      | Project pin-constraint file: edge, span and order per bus                              |
| `PIN_ARGS`         | make              | none      | Extra `place_pins` flags (minimum pin distance, corner avoidance)                      |
| pin length         | `1_floorplan.tcl` | 0.24 µm   | Pin landing depth; ↑ = easier access, slightly more boundary obstruction               |
| tap distance       | `1_floorplan.tcl` | 25 µm     | Latch-up margin vs a sliver of area                                                    |
| `cut_rows` halo    | `1_floorplan.tcl` | 1 µm      | Macro keep-out; ↑ = safer pin access, more lost placement area                         |
| PDN widths/pitches | strategy file     | see above | IR drop / EM margin vs signal-routing capacity on M5/M6                                |

## Notes and caveats

- **The PDN macro grid must match the macro's power pins.** The platform's default macro grids connect `{M4 M5}` — written for ORFS's SRAM macros. Blocks hardened by this flow (`MAX_ROUTE_LAYER=M5` with `pdn_tile.tcl`) expose their **M5 straps** as power pins and nothing on M6/M7, so the platform's macro grid finds no shapes and `pdngen` aborts with `PDN-0233 Failed to generate full power grid`. The fix is `scripts/pnr/pdn_macro.tcl` (auto-selected with `MACRO_DIRS`): its M6 mesh runs over the whole core, macros included, and its macro grid connects `{M5 M6}` — the parent's M6 straps dropped straight onto the block's M5 pins.
- **Pin depth is not cosmetic.** The 0.24 µm `set_pin_length` came from debugging macro-pin access; even with it, abstract-based routing can flag `Lef58EolKeepOut` markers at a macro pin — analyzed as false positives (the "obstruction" is the same net's continuation inside the block). Full story in [18_hierarchical.md](../concepts/hierarchical.md).
- **Utilization drifts upward through the flow**: the floorplan sets it by construction, but placement, CTS and routing repair all add buffers and up-sized cells — a few percent of growth is normal, and the knob should leave room for it.
- **Utilization is also a power knob**: a block hardened as a macro at low utilization carries longer internal wires than the same logic implemented flat, and the switching power of those wires is a measurable overhead. Harden blocks at higher utilization when power matters.
- **Snapping is normal**: a requested margin coming back slightly larger in the log is the tool aligning the core to sites and the manufacturing grid, not an error.

## Commercial perspective

Commercial floorplanning (Innovus `create_floorplan`/`floorPlan`, Fusion Compiler equivalents) covers the same objects with the same vocabulary — die/core, rows, tracks, utilization — plus a *power planning* step (`add_rings`, `add_stripes`) that mirrors `pdngen`'s strategy files. The additions of a production flow are chip-level: pad-ring and bump planning driven by an I/O assignment file, multi-domain floorplans with power switches and level shifters (UPF), macro placement assisted by dedicated engines, and signoff-grade IR/EM analysis closing the PDN loop. Conceptually, everything in this stage transfers one-to-one.

Source: [1_floorplan.tcl](../../pnr/1_floorplan.tcl) — [pdn_tile.tcl](../../pnr/pdn_tile.tcl) — [pdn_macro.tcl](../../pnr/pdn_macro.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)

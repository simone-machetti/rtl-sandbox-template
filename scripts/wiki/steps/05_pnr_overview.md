# P&R architecture — stages, checkpoints, helpers

Place-and-route is the largest step of the flow, so it is built differently from the single-script steps: six independent stages chained through database checkpoints, four shared helper scripts, and a thin sequencer. This document covers that architecture and the plumbing common to all stages; documents 09–14 cover the stages themselves.

## Inputs and outputs

**Inputs**

- Post-syn netlist `.v` (flat)
- Library of cells `.lib` (Liberty)
- Technology dimensions `.lef` (tech LEF + standard-cell LEF)
- Standard-cell layout `.gds` (for the final merge)
- Constraints, generated inline from `CLK_PERIOD_NS` (same scheme as the STA steps)
- ASAP7 platform physical setup (routing tracks, PDN grid strategy, wire RC, RC extraction rules)
- Hierarchical mode: hardened-block abstracts `.lef`/`.lib`/`.gds` (`MACRO_DIRS`) + project-owned macro-placement TCL (`FLOORPLAN`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `CORE_UTIL`, `ASPECT_RATIO`, `CORE_MARGIN`, `PLACE_DENSITY`, `CLK_UNCERTAINTY_PS`, `PNR_STEP`, `PNR_THREADS`, `MACRO_DIRS`, `FLOORPLAN`, `PDN` (optional)

**Outputs**

- Post-pnr netlist `.v` (routed, physical-only cells removed — same contract as the syn netlist)
- Post-pnr constraints `.sdc` (as implemented)
- Post-pnr parasitics `.spef` (OpenRCX extraction)
- Layout `.def` and `.gds`
- Database `.odb` (final + per-stage checkpoints)
- Hard-macro abstracts: `.lef` (abstract) + `.lib` (timing model) — for hierarchical place-and-route
- Post-pnr reports (per-stage timing/area, routing DRC, critical paths, WNS/TNS, clock skew, power, design area)

## Theory

### Why stages, why processes

P&R is naturally sequential — each phase (floorplan → placement → clock tree → routing → finishing) transforms the same design database and depends on its predecessor. Splitting the sequence into **separate tool processes connected by saved databases** buys three properties: *restartability* (rerun one stage from its predecessor's checkpoint instead of hours from scratch), *bounded memory* (each process starts clean; the OS reclaims everything between stages), and *clean logs* (one file per stage, trivially diffable across runs). The cost is re-loading context in every process — which is exactly what the helper scripts standardize.

### What a checkpoint does and does not contain

OpenROAD's database, **ODB**, persists the design: netlist, technology, placement, routing, power grid — everything geometric and structural. It does **not** persist the analysis context: SDC constraints, wire-RC settings, and engine settings (`set_dont_use`, thread count) live only in the process's memory. Every stage therefore re-establishes that context after loading the database — centralized in `load_checkpoint` and `init_tech.tcl` so no stage can forget it.

## Implementation walkthrough

### The Makefile target

```make
pnr: $(if $(filter all,$(PNR_STEP)),clean-imp)
	cd $(REPO_HOME)/scripts/pnr && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	./run.sh
```

The one subtlety: the clean-prerequisite is *conditional*. A full run (`PNR_STEP=all`, the default) starts from a wiped `OUT_DIR`, preserving the flow-wide "every target starts clean" guarantee; a single-stage rerun (`PNR_STEP=3_cts`) must *keep* the directory — its input is the previous stage's checkpoint living there.

### The sequencer — `scripts/pnr/run.sh`

```bash
set -euo pipefail

PROJ="${REPO_HOME}/projects/${SEL_PROJECT}"
IMP="${PROJ}/imp/${SEL_OUT_DIR}"

STAGES="1_floorplan 2_place 3_cts 4_route 5_final 6_gds"
if [ "${SEL_PNR_STEP}" != "all" ]; then
    STAGES="${SEL_PNR_STEP}"
fi

for stage in ${STAGES}; do
    if [ "${stage}" = "6_gds" ]; then
        "${REPO_HOME}/scripts/pnr/6_gds.sh" \
            2>&1 | tee "${IMP}/output/klayout_${stage}.log"
    else
        openroad -exit -no_init -no_splash "${REPO_HOME}/scripts/pnr/${stage}.tcl" \
            2>&1 | tee "${IMP}/output/openroad_${stage}.log"
    fi
done
```

A loop over the stage list (or the single requested stage). Each OpenROAD stage runs batch (`-exit`), ignoring any user config (`-no_init`) for reproducibility, teeing its transcript to a per-stage log; `set -o pipefail` makes a failing stage abort the whole run despite the `tee`. Stage 6 is not an OpenROAD script — the GDS merge is KLayout's job ([11_pnr_gds.md](11_pnr_gds.md)) — so the sequencer dispatches to its shell script.

### Context — `scripts/pnr/init_tech.tcl` (sourced first by every stage)

```tcl
set OUT_DIR    $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_OUT_DIR)/output
set REPORT_DIR $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_OUT_DIR)/report

source $::env(ASAP7_HOME)/liberty_suppressions.tcl

read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

if {$::env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $::env(SEL_MACRO_DIRS) {
        read_liberty $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$dir/output/timing_model.lib
    }
}
```

Directories, a benign-warning suppression, and the liberty set — plus, in hierarchical runs, each hardened block's timing model. Liberty is loaded in *every* stage process because timing models are not part of the ODB.

```tcl
set TECH_LEF        $::env(ASAP7_HOME)/lef/asap7_tech_1x_201209.lef
set SC_LEF          $::env(ASAP7_HOME)/lef/asap7sc7p5t_28_R_1x_220121a.lef
set SITE            asap7sc7p5t
set PIN_LAYER_HOR   M4
set PIN_LAYER_VER   M5
set MIN_ROUTE_LAYER M2
set MAX_ROUTE_LAYER M7
set MIN_CLK_LAYER   M4
set TAPCELL         TAPCELL_ASAP7_75t_R
set TIEHI_PORT      TIEHIx1_ASAP7_75t_R/H
set TIELO_PORT      TIELOx1_ASAP7_75t_R/L
set FILL_CELLS      {FILLERxp5_ASAP7_75t_R FILLER_ASAP7_75t_R DECAPx1_ASAP7_75t_R \
                     DECAPx2_ASAP7_75t_R DECAPx4_ASAP7_75t_R DECAPx6_ASAP7_75t_R \
                     DECAPx10_ASAP7_75t_R}
set DONT_USE        {*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}
```

The technology settings in one place: physical view paths, the placement site, pin and routing layer choices, and the special-cell roster (tap/tie/filler masters and the optimizer blacklist) — each choice explained in the stage document that consumes it (09 for floorplan items, 12 for routing layers).

```tcl
if {$::env(SEL_PDN) ne "none"} {
    set PDN_CFG $::env(SEL_PDN)
} elseif {$::env(SEL_MACRO_DIRS) ne "none"} {
    set PDN_CFG $::env(REPO_HOME)/scripts/pnr/pdn_macro.tcl
} else {
    set PDN_CFG $::env(ASAP7_HOME)/openRoad/pdn/grid_strategy-M1-M2-M5-M6.tcl
}

if {$::env(SEL_PNR_THREADS) > 0} {
    set_thread_count $::env(SEL_PNR_THREADS)
} else {
    set_thread_count [exec nproc]
}
```

PDN strategy selection (explicit override > macro-aware default > platform default) and the thread policy: all cores unless capped. The cap matters because detailed routing's memory peak scales with its parallel workers — `PNR_THREADS` is the flow's memory/runtime dial.

### Checkpoints — `scripts/pnr/checkpoint.tcl`

```tcl
proc save_checkpoint {tag} {
    global OUT_DIR
    write_db $OUT_DIR/${tag}.odb
}

proc load_checkpoint {tag} {
    global OUT_DIR DONT_USE
    read_db $OUT_DIR/${tag}.odb
    source $::env(REPO_HOME)/scripts/pnr/constraints.tcl
    source $::env(ASAP7_HOME)/setRC.tcl
    set_dont_use $DONT_USE
}
```

The persistence contract in code: saving is just `write_db`; loading is `read_db` **plus the three context re-applications** — constraints ([02_constraints.md](../concepts/constraints.md)), wire RC estimates, and the optimizer blacklist — precisely the things ODB does not store. Keeping that knowledge in one proc is what makes six independent processes behave like one continuous session.

### Reports — `scripts/pnr/reports.tcl`

```tcl
proc report_design_area_file {file} {
    set block       [ord::get_db_block]
    set dbu         [expr {double([$block getDbUnitsPerMicron])}]
    set core        [$block getCoreArea]
    set core_area   [expr {[$core dx] * [$core dy] / ($dbu * $dbu)}]
    set design_area [expr {[rsz::design_area] * 1e12}]
    set util        [expr {$design_area / $core_area * 100.0}]
    set fh [open $file a]
    puts $fh [format "Design area %.0f u^2 %.0f%% utilization." $design_area $util]
    close $fh
}

proc report_stage {tag} {
    global REPORT_DIR
    report_checks \
        -path_delay max \
        -fields {slew cap} \
        -digits 4 \
        > $REPORT_DIR/${tag}.rpt
    report_wns >> $REPORT_DIR/${tag}.rpt
    report_tns >> $REPORT_DIR/${tag}.rpt
    report_design_area_file $REPORT_DIR/${tag}.rpt
}
```

Every stage ends with the same snapshot: worst path with slews/caps, WNS, TNS, and area/utilization — so timing and area can be tracked *across* stages (the honest way to see what CTS or routing cost). The area helper computes from the database directly because OpenROAD's `report_design_area` prints to the log and ignores OpenSTA-style file redirection — an example of the small tool-behavior discoveries a hand-built flow accumulates.

## Design space

- **Staged vs monolithic**: one long script (all stages, one process) is simpler and avoids reload cost, but loses restartability and per-stage memory reclamation — for multi-hour routing runs, restartability wins decisively.
- **Checkpoint format**: ODB is binary and complete; DEF is the interchange alternative (portable, but lossy for tool state). Compressing/bundling checkpoints is a housekeeping option for large designs.
- **Finer stage granularity** (splitting placement into global/detailed processes, routing into global/detailed) buys finer restart points at more reload overhead — the six-stage cut matches the natural checkpoints people actually want to rerun from.
- **Reference flows**: ORFS drives the same OpenROAD binary with a large generic Makefile system; this flow trades its generality for scripts short enough to read — the premise of this course.

## Knobs

| Knob          | Where | Default  | Effect / tradeoff                                                    |
| ------------- | ----- | -------- | -------------------------------------------------------------------- |
| `PNR_STEP`    | make  | all      | Full clean run vs single-stage rerun from the previous checkpoint    |
| `PNR_THREADS` | make  | 0 (=all) | Parallelism; fewer route threads = lower memory peak, longer runtime |
| `PDN`         | make  | auto     | PDN strategy file (see selection logic above)                        |
| `MACRO_DIRS`  | make  | none     | Hierarchical mode master switch (affects every stage's context)      |

## Notes and caveats

- A single-stage rerun (`PNR_STEP=<stage>`) intentionally skips the clean; it requires the same `OUT_DIR` to still hold the predecessor checkpoint — and inherits whatever parameters that checkpoint was built with, except the ones re-applied from the environment (constraints!). Changing `CLK_PERIOD_NS` and rerunning a late stage is therefore *possible* but produces a mixed-target result; full reruns are the honest experiment.
- `set_dont_use` and thread count are per-process settings — the reason they live in `init_tech.tcl`/`load_checkpoint` rather than in any one stage.
- Stage logs are the primary debugging artifact; each stage's log contains that stage only, and the `report/<stage>.rpt` series shows the timing/area trajectory across the flow.
- Runtime and memory are dominated by detailed routing; the per-stage process model means its peak defines the machine requirement.

## Commercial perspective

Commercial P&R (Innovus, Fusion Compiler) is one long-lived session over a proprietary database, with the same conceptual checkpoints (`saveDesign`/restore) and the same stage vocabulary. The one-process-per-stage discipline here is closer to how those tools are *scripted in production* anyway — reference flows save and restore between named steps for exactly the restartability reasons above.

Source: [run.sh](../../pnr/run.sh) — [init_tech.tcl](../../pnr/init_tech.tcl) — [checkpoint.tcl](../../pnr/checkpoint.tcl) — [reports.tcl](../../pnr/reports.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)

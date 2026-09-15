# P&R stage 6 — GDS merge

The last transformation: from the router's placed-and-wired abstraction to real mask geometry. The DEF is streamed into polygons and every cell abstract is replaced by its true transistor-level layout.

## Inputs and outputs

- **Inputs**: `output/design.def`, the ASAP7 technology/cell LEFs, the library cell GDS; in hierarchical runs, each hardened block's `abstract.lef` and `design.gds`.
- **Outputs**: `output/design.gds` (the merged final layout) and the generated `output/klayout.lyt` viewing/translation setup.

## Theory

**GDSII** is the sign-off geometry format: a binary tree of *structures* (cells), each a list of polygons on numbered *layers*, plus placements of other structures — the file that (after mask preparation) becomes the photomasks. Nothing in it knows about nets, timing or cells' logical function; it is pure geometry at database-unit resolution.

The step's job is a *merge*: the P&R database contains exact positions and wire shapes but only **abstract** cells; the library GDS contains every cell's **real polygons** but no placement. Streaming DEF→GDS creates the top structure (wires, vias, pin shapes as drawn geometry) with each cell instance referencing its structure by name; merging the library GDS then substitutes those references with the real layouts. Name matching is the entire mechanism — every LEF macro must have an identically-named GDS structure.

Why an external tool: OpenROAD deliberately does not write GDS; **KLayout** — the open-source layout editor — has a full LEF/DEF/GDS translation engine and is scriptable in batch mode. It needs a *technology file* (`.lyt`) telling its reader how to interpret DEF against the LEFs (layer numbering, units, which LEFs define the cells).

## Implementation walkthrough

`scripts/pnr/6_gds.sh`:

```bash
set -euo pipefail

PROJ="${REPO_HOME}/projects/${SEL_PROJECT}"
IMP="${PROJ}/imp/${SEL_OUT_DIR}"

if ! command -v klayout > /dev/null; then
    echo "Error: klayout not found on PATH: cannot merge design.def into design.gds." >&2
    exit 1
fi
```

KLayout is the one tool of the flow that may legitimately be absent (system-installed, not part of the EDA tree); the guard fails the stage with a clear message — everything before it (DEF/ODB, reports) already exists, so a missing KLayout costs only the GDS.

```bash
TECH_LEF="${ASAP7_HOME}/lef/asap7_tech_1x_201209.lef"
SC_LEF="${ASAP7_HOME}/lef/asap7sc7p5t_28_R_1x_220121a.lef"
SC_GDS="${ASAP7_HOME}/gds/asap7sc7p5t_28_R_220121a.gds"

LEF_FILES="<lef-files>${TECH_LEF}</lef-files><lef-files>${SC_LEF}</lef-files>"
IN_FILES="${SC_GDS}"
if [ "${SEL_MACRO_DIRS}" != "none" ]; then
    for dir in ${SEL_MACRO_DIRS}; do
        LEF_FILES="${LEF_FILES}<lef-files>${PROJ}/imp/${dir}/output/abstract.lef</lef-files>"
        IN_FILES="${IN_FILES} ${PROJ}/imp/${dir}/output/design.gds"
    done
fi

sed "s,<lef-files>.*</lef-files>,${LEF_FILES}," \
    "${ASAP7_HOME}/KLayout/asap7.lyt" > "${IMP}/output/klayout.lyt"
```

The technology-file preparation. The platform ships `asap7.lyt` with a *relative* LEF path that only resolves from inside the platform tree, so the script rewrites its `<lef-files>` entry with absolute paths — tech LEF plus cell LEF, extended in hierarchical runs with each block's abstract (so the DEF reader knows the macros' outlines) while each block's *GDS* joins the merge list (so the abstracts get substituted by the blocks' real layouts). The generated `klayout.lyt` is kept in the run directory — it doubles as a ready-made viewing setup.

```bash
klayout -zz \
    -rd design_name="${SEL_TOP_LEVEL}" \
    -rd in_def="${IMP}/output/design.def" \
    -rd in_files="${IN_FILES}" \
    -rd seal_file="" \
    -rd layer_map="" \
    -rd out_file="${IMP}/output/design.gds" \
    -rd tech_file="${IMP}/output/klayout.lyt" \
    -r "${REPO_HOME}/scripts/pnr/def2stream.py"
```

Headless KLayout (`-zz`), parameterized (`-rd name=value`) and running `def2stream.py` — the standard DEF-to-stream script (kept in-repo, taken from the reference flow ecosystem; third-party code, not authored here). It reads the DEF with the technology setup, merges the `in_files` GDS libraries, verifies that every LEF cell found a matching GDS structure and that no unexpected top-level structures remain ("orphans"), and writes the final `design.gds` under the top structure named `design_name`. The `seal_file`/`layer_map` parameters exist for chip-finishing features unused in this block-level flow (empty values).

## Design space

- **Chip finishing**: a tapeout adds steps this flow deliberately omits — **metal fill** (dummy geometry for density rules), **seal ring** (the die-edge structure; the `seal_file` hook), logos/markers — all KLayout-scriptable in the same framework.
- **Physical verification**: the merged GDS is what DRC and LVS run against (KLayout has a DRC engine and rule decks exist for ASAP7; commercial signoff uses Calibre/Pegasus). This flow's "DRC" is the router's own check ([09_pnr_route.md](09_pnr_route.md)); polygon-level verification is the next rigor step.
- **OASIS** is GDSII's denser modern successor — a format switch, same content.
- **Layer mapping** (`layer_map`): translating tool layer numbers to foundry mask numbers — identity for ASAP7, a real map at any foundry.

## Knobs

| Knob         | Where      | Default | Effect / tradeoff                                      |
| ------------ | ---------- | ------- | ------------------------------------------------------ |
| `MACRO_DIRS` | make       | none    | Adds each block's abstract (reading) and GDS (merging) |
| `seal_file`  | `6_gds.sh` | empty   | Chip-finishing hook (unused at block level)            |
| `layer_map`  | `6_gds.sh` | empty   | Tool-to-mask layer translation (identity for ASAP7)    |

## Notes and caveats

- The log's success criteria are explicit: `All LEF cells have matching GDS/OAS cells` and `No orphan cells in the final layout` — name-matching is the whole game, and those two lines confirm it worked.
- A DEF-units-vs-reader-DBU warning from KLayout is benign: the reader converts units; geometry is unaffected.
- The merged GDS is large (every polygon of every cell instance); it is a per-run product like everything else in `output/`.
- The generated `klayout.lyt` is the convenient way to *view* the result: opening `design.gds` in KLayout with it gives named layers.
- Requires KLayout ≥ 0.28 (older distribution packages predate the needed LEF/DEF engine features).

## Commercial perspective

In commercial flows the same merge happens inside the P&R tool (`streamOut`) or in signoff data-prep, followed by the full finishing/verification chain: metal fill, DRC/LVS with foundry decks, and mask data preparation. The DEF+LEF+GDS-libraries → merged-GDS pattern is identical; only the executor differs.

Source: [6_gds.sh](../../pnr/6_gds.sh) — [def2stream.py](../../pnr/def2stream.py) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)

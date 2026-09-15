#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set -euo pipefail

PROJ="${REPO_HOME}/projects/${SEL_PROJECT}"
IMP="${PROJ}/imp/${SEL_OUT_DIR}"

if ! command -v klayout > /dev/null; then
    echo "Error: klayout not found on PATH: cannot merge design.def into design.gds." >&2
    exit 1
fi

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

klayout -zz \
    -rd design_name="${SEL_TOP_LEVEL}" \
    -rd in_def="${IMP}/output/design.def" \
    -rd in_files="${IN_FILES}" \
    -rd seal_file="" \
    -rd layer_map="" \
    -rd out_file="${IMP}/output/design.gds" \
    -rd tech_file="${IMP}/output/klayout.lyt" \
    -r "${REPO_HOME}/scripts/pnr/def2stream.py"

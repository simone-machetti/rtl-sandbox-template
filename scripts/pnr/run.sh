#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

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

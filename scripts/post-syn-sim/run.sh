#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set -euo pipefail

PROJ="${REPO_HOME}/projects/${SEL_PROJECT}"
SIM="${PROJ}/sim/${SEL_OUT_DIR}"

g_flags=()
if [ "${SEL_PARAMS}" != "none" ]; then
    for param in ${SEL_PARAMS}; do
        g_flags+=("-G${param}")
    done
fi

vlt_files=()
while IFS= read -r f; do
    vlt_files+=("$f")
done < <(find "${PROJ}/rtl" -name "*.vlt" | sort)

trace_flags=()
if [ "${SEL_VCD:-0}" = "1" ]; then
    trace_flags=(--trace --trace-underscore --trace-max-array 0 --trace-max-width 0 -DVCD)
fi

verilator \
    -sv \
    --build-jobs 0 \
    --binary \
    --timing \
    --output-split 20000 \
    "${trace_flags[@]}" \
    -Wall \
    -Wno-fatal \
    -Wno-SPECIFYIGN \
    -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL \
    -Wno-UNDRIVEN \
    -DPOST_SYN_SIM \
    -DCLK_PERIOD_NS="${SEL_CLK_PERIOD_NS}" \
    "${g_flags[@]}" \
    "${vlt_files[@]}" \
    --x-initial fast \
    --x-assign fast \
    --top-module "${SEL_TB}" \
    -f "${REPO_HOME}/scripts/post-syn-sim/filelist.f" \
       "${PROJ}/tb/${SEL_TB}.sv" \
    -Mdir "${SIM}/build/obj_dir" \
    -o "${SIM}/build/simv" \
    | tee "${SIM}/output/compile.log"

exec "${SIM}/build/simv" "$@" \
    | tee "${SIM}/output/run.log"

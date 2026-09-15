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

inc_flags=()
while IFS= read -r d; do
    inc_flags+=(-I"$d")
done < <(find "${PROJ}/rtl" -type d | sort)

vlt_files=()
while IFS= read -r f; do
    vlt_files+=("$f")
done < <(find "${PROJ}/rtl" -name "*.vlt" | sort)

trace_flags=()
if [ "${SEL_VCD:-0}" = "1" ]; then
    trace_flags=(--trace --trace-max-array 0 --trace-max-width 0 --output-split 20000 -DVCD)
fi

verilator \
    -sv \
    --build-jobs 0 \
    --binary \
    --timing \
    "${trace_flags[@]}" \
    -Wall \
    -Wno-fatal \
    -DCLK_PERIOD_NS="${SEL_CLK_PERIOD_NS}" \
    "${g_flags[@]}" \
    "${inc_flags[@]}" \
    "${vlt_files[@]}" \
    --top-module "${SEL_TB}" \
    "${PROJ}/tb/${SEL_TB}.sv" \
    -Mdir "${SIM}/build/obj_dir" \
    -o "${SIM}/build/simv" \
    | tee "${SIM}/output/compile.log"

exec "${REPO_HOME}/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/build/simv" "$@" \
    | tee "${REPO_HOME}/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/output/run.log"

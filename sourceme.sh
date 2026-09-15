#!/bin/bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export REPO_HOME="${REPO_HOME:-$_SCRIPT_DIR}"

source ~/.bashrc

: "${ASAP7_HOME:=$PDK_HOME/OpenROAD-flow-scripts/flow/platforms/asap7}"
export ASAP7_HOME

unset _SCRIPT_DIR

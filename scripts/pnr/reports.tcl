# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

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

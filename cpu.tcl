# Vivado Tcl project template
# Run:
#   vivado -mode batch -source cpu.tcl
# or enter Tcl shell first:
#   vivado -mode tcl
#   source cpu.tcl

# -----------------------------
# 1. Edit these variables first
# -----------------------------
# 所有路径相对于 cpu.tcl 所在目录，允许从其他工作目录 source。
set source_dir [file dirname [file normalize [info script]]]
set project_name "cpu"
set project_dir [file join $source_dir "prj"]

# Example parts:
#   xc7a35tcsg324-1    ;# Artix-7, often used by Basys 3
#   xc7z020clg400-1    ;# Zynq-7020
#   xcku040-ffva1156-2 ;# Kintex UltraScale
set part_name "xczu5ev-sfvc784-2-e"

# Top module/entity name
set top_name "cpu_loader_top"

# 从 rtl.f 读取设计源文件：core/、loader/ 和 cpu_loader_top.sv。
# 测试平台、C 程序和启动汇编不加入 sources_1。
set rtl_files [list]
set rtl_list [open [file join $source_dir "rtl.f"] r]
foreach entry [split [read $rtl_list] "\n"] {
    set entry [string trim $entry]
    if {$entry ne "" && ![string match "#*" $entry]} {
        lappend rtl_files [file join $source_dir $entry]
    }
}
close $rtl_list

# define.sv 是头文件；显式设置类型，避免作为独立模块编译。
set header_file [file join $source_dir "core" "define.sv"]
set xdc_files [list [file join $source_dir "cpu.xdc"]]

#add personal or official ip
#set ip_files [list \
#    "./ip/my_ip.xci" \
#]

# -----------------------------
# 2. Create/open project
# -----------------------------
create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# -----------------------------
# 3. Add source files
# -----------------------------
foreach file_path $rtl_files {
    if {[file exists $file_path]} {
        add_files -fileset sources_1 $file_path
    } else {
        error "RTL file not found: $file_path"
    }
}

if {![file exists $header_file]} {
    error "Header file not found: $header_file"
}
add_files -fileset sources_1 $header_file
set_property file_type {Verilog Header} [get_files $header_file]
set_property include_dirs [list [file join $source_dir "core"]] [get_filesets sources_1]

foreach file_path $xdc_files {
    if {[file exists $file_path]} {
        add_files -fileset constrs_1 $file_path
    } else {
        puts "WARNING: XDC file not found: $file_path"
    }
}

#foreach file_path $ip_files {
#    if {[file exists $file_path]} {
#        add_files -fileset sources_1 $file_path
#        generate_target all [get_files $file_path]
#    } else {
#        puts "WARNING: IP file not found: $file_path"
#    }
#}

set_property top $top_name [get_filesets sources_1]
update_compile_order -fileset sources_1

# -----------------------------
# 4. Run synthesis
# -----------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis did not finish successfully."
}

open_run synth_1
report_timing_summary -file "$project_dir/timing_synth.rpt"
report_utilization -file "$project_dir/util_synth.rpt"

# -----------------------------
# 5. Run implementation
# -----------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation did not finish successfully."
}

open_run impl_1
report_timing_summary -file "$project_dir/timing_impl.rpt"
report_utilization -file "$project_dir/util_impl.rpt"

puts "DONE: bitstream and reports are in $project_dir"

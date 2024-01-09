
################################################################
# This is a generated script based on design: top
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2022.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source top_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# daq_axis

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xczu28dr-ffvg1517-2-e
   set_property BOARD_PART xilinx.com:zcu111:part0:1.4 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name top

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:clk_wiz:6.0\
xilinx.com:ip:axis_data_fifo:2.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:axi_dma:7.1\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:ip:usp_rf_data_converter:2.6\
xilinx.com:ip:zynq_ultra_ps_e:3.4\
xilinx.com:ip:axis_dwidth_converter:1.1\
xilinx.com:ip:axi_fifo_mm_s:4.2\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
daq_axis\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################


# Hierarchical cell: trigger_manager_config
proc create_hier_cell_trigger_manager_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_trigger_manager_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: sample_discriminator_config
proc create_hier_cell_sample_discriminator_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_sample_discriminator_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: axis_dwidth_converter_0, and set properties
  set axis_dwidth_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_0 ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $axis_dwidth_converter_0


  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins M_AXIS] [get_bd_intf_pins axis_dwidth_converter_0/M_AXIS]
  connect_bd_intf_net -intf_net sample_discriminator_config_AXI_STR_TXD [get_bd_intf_pins axis_dwidth_converter_0/S_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins axis_dwidth_converter_0/aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins axis_dwidth_converter_0/aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: lmh6401_config
proc create_hier_cell_lmh6401_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_lmh6401_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: dds_phase_inc
proc create_hier_cell_dds_phase_inc { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_dds_phase_inc() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: axis_dwidth_converter_0, and set properties
  set axis_dwidth_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_0 ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $axis_dwidth_converter_0


  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins M_AXIS] [get_bd_intf_pins axis_dwidth_converter_0/M_AXIS]
  connect_bd_intf_net -intf_net sample_discriminator_config_AXI_STR_TXD [get_bd_intf_pins axis_dwidth_converter_0/S_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins axis_dwidth_converter_0/aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins axis_dwidth_converter_0/aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: dac_scale_config
proc create_hier_cell_dac_scale_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_dac_scale_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: axis_dwidth_converter_0, and set properties
  set axis_dwidth_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_0 ]
  set_property CONFIG.M_TDATA_NUM_BYTES {18} $axis_dwidth_converter_0


  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins M_AXIS] [get_bd_intf_pins axis_dwidth_converter_0/M_AXIS]
  connect_bd_intf_net -intf_net sample_discriminator_config_AXI_STR_TXD [get_bd_intf_pins axis_dwidth_converter_0/S_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins axis_dwidth_converter_0/aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins axis_dwidth_converter_0/aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: dac_mux_config
proc create_hier_cell_dac_mux_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_dac_mux_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: buffer_timestamp_width
proc create_hier_cell_buffer_timestamp_width { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_buffer_timestamp_width() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 AXI_STR_RXD

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk s_axi_aclk
  create_bd_pin -dir I -type rst s_axi_aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_TX_CTRL {0} \
    CONFIG.C_USE_TX_DATA {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins AXI_STR_RXD] [get_bd_intf_pins fifo/AXI_STR_RXD]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]

  # Create port connections
  connect_bd_net -net s_axi_aclk_1 [get_bd_pins s_axi_aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net s_axi_aresetn_1 [get_bd_pins s_axi_aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: buffer_start_stop
proc create_hier_cell_buffer_start_stop { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_buffer_start_stop() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: buffer_config
proc create_hier_cell_buffer_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_buffer_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: awg_trigger_out_config
proc create_hier_cell_awg_trigger_out_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_awg_trigger_out_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: awg_start_stop
proc create_hier_cell_awg_start_stop { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_awg_start_stop() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: awg_frame_depth
proc create_hier_cell_awg_frame_depth { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_awg_frame_depth() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: axis_dwidth_converter_0, and set properties
  set axis_dwidth_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_0 ]
  set_property CONFIG.M_TDATA_NUM_BYTES {12} $axis_dwidth_converter_0


  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins M_AXIS] [get_bd_intf_pins axis_dwidth_converter_0/M_AXIS]
  connect_bd_intf_net -intf_net sample_discriminator_config_AXI_STR_TXD [get_bd_intf_pins axis_dwidth_converter_0/S_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins axis_dwidth_converter_0/aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins axis_dwidth_converter_0/aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: awg_dma_error
proc create_hier_cell_awg_dma_error { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_awg_dma_error() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 AXI_STR_RXD

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk s_axi_aclk
  create_bd_pin -dir I -type rst s_axi_aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_TX_CTRL {0} \
    CONFIG.C_USE_TX_DATA {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins AXI_STR_RXD] [get_bd_intf_pins fifo/AXI_STR_RXD]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]

  # Create port connections
  connect_bd_net -net s_axi_aclk_1 [get_bd_pins s_axi_aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net s_axi_aresetn_1 [get_bd_pins s_axi_aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: awg_burst_length
proc create_hier_cell_awg_burst_length { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_awg_burst_length() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: axis_dwidth_converter_0, and set properties
  set axis_dwidth_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_0 ]
  set_property CONFIG.M_TDATA_NUM_BYTES {64} $axis_dwidth_converter_0


  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins M_AXIS] [get_bd_intf_pins axis_dwidth_converter_0/M_AXIS]
  connect_bd_intf_net -intf_net sample_discriminator_config_AXI_STR_TXD [get_bd_intf_pins axis_dwidth_converter_0/S_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins axis_dwidth_converter_0/aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins axis_dwidth_converter_0/aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: adc_mux_config
proc create_hier_cell_adc_mux_config { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_adc_mux_config() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: fifo, and set properties
  set fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.2 fifo ]
  set_property -dict [list \
    CONFIG.C_USE_RX_DATA {0} \
    CONFIG.C_USE_TX_CTRL {0} \
  ] $fifo


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins S_AXI] [get_bd_intf_pins fifo/S_AXI]
  connect_bd_intf_net -intf_net fifo_AXI_STR_TXD [get_bd_intf_pins M_AXIS] [get_bd_intf_pins fifo/AXI_STR_TXD]

  # Create port connections
  connect_bd_net -net Net1 [get_bd_pins aclk] [get_bd_pins fifo/s_axi_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins aresetn] [get_bd_pins fifo/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: adc_cdc
proc create_hier_cell_adc_cdc { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_adc_cdc() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_00

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_02

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_10

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_12

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_20

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_22

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_30

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M_AXIS_32

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_00

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_02

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_10

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_12

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_20

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_22

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_30

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS_32


  # Create pins
  create_bd_pin -dir I -type clk m_axis_aclk
  create_bd_pin -dir I -type clk s_axis_aclk
  create_bd_pin -dir I -type rst s_axis_aresetn

  # Create instance: adc00_cdc, and set properties
  set adc00_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc00_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc00_cdc


  # Create instance: adc00_wconv, and set properties
  set adc00_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc00_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc00_wconv


  # Create instance: adc02_cdc, and set properties
  set adc02_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc02_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc02_cdc


  # Create instance: adc02_wconv, and set properties
  set adc02_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc02_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc02_wconv


  # Create instance: adc10_cdc, and set properties
  set adc10_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc10_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc10_cdc


  # Create instance: adc10_wconv, and set properties
  set adc10_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc10_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc10_wconv


  # Create instance: adc12_cdc, and set properties
  set adc12_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc12_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc12_cdc


  # Create instance: adc12_wconv, and set properties
  set adc12_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc12_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc12_wconv


  # Create instance: adc20_cdc, and set properties
  set adc20_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc20_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc20_cdc


  # Create instance: adc20_wconv, and set properties
  set adc20_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc20_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc20_wconv


  # Create instance: adc22_cdc, and set properties
  set adc22_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc22_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc22_cdc


  # Create instance: adc22_wconv, and set properties
  set adc22_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc22_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc22_wconv


  # Create instance: adc30_cdc, and set properties
  set adc30_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc30_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc30_cdc


  # Create instance: adc30_wconv, and set properties
  set adc30_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc30_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc30_wconv


  # Create instance: adc32_cdc, and set properties
  set adc32_cdc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc32_cdc ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc32_cdc


  # Create instance: adc32_wconv, and set properties
  set adc32_wconv [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 adc32_wconv ]
  set_property CONFIG.M_TDATA_NUM_BYTES {32} $adc32_wconv


  # Create interface connections
  connect_bd_intf_net -intf_net S_AXIS_00_1 [get_bd_intf_pins S_AXIS_00] [get_bd_intf_pins adc00_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_02_1 [get_bd_intf_pins S_AXIS_02] [get_bd_intf_pins adc02_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_10_1 [get_bd_intf_pins S_AXIS_10] [get_bd_intf_pins adc10_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_12_1 [get_bd_intf_pins S_AXIS_12] [get_bd_intf_pins adc12_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_20_1 [get_bd_intf_pins S_AXIS_20] [get_bd_intf_pins adc20_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_22_1 [get_bd_intf_pins S_AXIS_22] [get_bd_intf_pins adc22_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_30_1 [get_bd_intf_pins S_AXIS_30] [get_bd_intf_pins adc30_wconv/S_AXIS]
  connect_bd_intf_net -intf_net S_AXIS_32_1 [get_bd_intf_pins S_AXIS_32] [get_bd_intf_pins adc32_wconv/S_AXIS]
  connect_bd_intf_net -intf_net adc00_wconv_M_AXIS [get_bd_intf_pins adc00_cdc/S_AXIS] [get_bd_intf_pins adc00_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc02_wconv_M_AXIS [get_bd_intf_pins adc02_cdc/S_AXIS] [get_bd_intf_pins adc02_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc10_cdc_M_AXIS [get_bd_intf_pins M_AXIS_10] [get_bd_intf_pins adc10_cdc/M_AXIS]
  connect_bd_intf_net -intf_net adc10_wconv_M_AXIS [get_bd_intf_pins adc10_cdc/S_AXIS] [get_bd_intf_pins adc10_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc12_cdc_M_AXIS [get_bd_intf_pins M_AXIS_12] [get_bd_intf_pins adc12_cdc/M_AXIS]
  connect_bd_intf_net -intf_net adc12_wconv_M_AXIS [get_bd_intf_pins adc12_cdc/S_AXIS] [get_bd_intf_pins adc12_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc20_cdc_M_AXIS [get_bd_intf_pins M_AXIS_20] [get_bd_intf_pins adc20_cdc/M_AXIS]
  connect_bd_intf_net -intf_net adc20_wconv_M_AXIS [get_bd_intf_pins adc20_cdc/S_AXIS] [get_bd_intf_pins adc20_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc22_cdc_M_AXIS [get_bd_intf_pins M_AXIS_22] [get_bd_intf_pins adc22_cdc/M_AXIS]
  connect_bd_intf_net -intf_net adc22_wconv_M_AXIS [get_bd_intf_pins adc22_cdc/S_AXIS] [get_bd_intf_pins adc22_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc30_cdc_M_AXIS [get_bd_intf_pins M_AXIS_30] [get_bd_intf_pins adc30_cdc/M_AXIS]
  connect_bd_intf_net -intf_net adc30_wconv_M_AXIS [get_bd_intf_pins adc30_cdc/S_AXIS] [get_bd_intf_pins adc30_wconv/M_AXIS]
  connect_bd_intf_net -intf_net adc32_cdc_M_AXIS [get_bd_intf_pins M_AXIS_32] [get_bd_intf_pins adc32_cdc/M_AXIS]
  connect_bd_intf_net -intf_net adc32_wconv_M_AXIS [get_bd_intf_pins adc32_cdc/S_AXIS] [get_bd_intf_pins adc32_wconv/M_AXIS]
  connect_bd_intf_net -intf_net axis_data_fifo_0_M_AXIS [get_bd_intf_pins M_AXIS_00] [get_bd_intf_pins adc00_cdc/M_AXIS]
  connect_bd_intf_net -intf_net axis_data_fifo_1_M_AXIS [get_bd_intf_pins M_AXIS_02] [get_bd_intf_pins adc02_cdc/M_AXIS]

  # Create port connections
  connect_bd_net -net Net [get_bd_pins s_axis_aresetn] [get_bd_pins adc00_cdc/s_axis_aresetn] [get_bd_pins adc00_wconv/aresetn] [get_bd_pins adc02_cdc/s_axis_aresetn] [get_bd_pins adc02_wconv/aresetn] [get_bd_pins adc10_cdc/s_axis_aresetn] [get_bd_pins adc10_wconv/aresetn] [get_bd_pins adc12_cdc/s_axis_aresetn] [get_bd_pins adc12_wconv/aresetn] [get_bd_pins adc20_cdc/s_axis_aresetn] [get_bd_pins adc20_wconv/aresetn] [get_bd_pins adc22_cdc/s_axis_aresetn] [get_bd_pins adc22_wconv/aresetn] [get_bd_pins adc30_cdc/s_axis_aresetn] [get_bd_pins adc30_wconv/aresetn] [get_bd_pins adc32_cdc/s_axis_aresetn] [get_bd_pins adc32_wconv/aresetn]
  connect_bd_net -net adc_clk_512_out [get_bd_pins s_axis_aclk] [get_bd_pins adc00_cdc/s_axis_aclk] [get_bd_pins adc00_wconv/aclk] [get_bd_pins adc02_cdc/s_axis_aclk] [get_bd_pins adc02_wconv/aclk] [get_bd_pins adc10_cdc/s_axis_aclk] [get_bd_pins adc10_wconv/aclk] [get_bd_pins adc12_cdc/s_axis_aclk] [get_bd_pins adc12_wconv/aclk] [get_bd_pins adc20_cdc/s_axis_aclk] [get_bd_pins adc20_wconv/aclk] [get_bd_pins adc22_cdc/s_axis_aclk] [get_bd_pins adc22_wconv/aclk] [get_bd_pins adc30_cdc/s_axis_aclk] [get_bd_pins adc30_wconv/aclk] [get_bd_pins adc32_cdc/s_axis_aclk] [get_bd_pins adc32_wconv/aclk]
  connect_bd_net -net usp_rf_data_converter_0_clk_adc0 [get_bd_pins m_axis_aclk] [get_bd_pins adc00_cdc/m_axis_aclk] [get_bd_pins adc02_cdc/m_axis_aclk] [get_bd_pins adc10_cdc/m_axis_aclk] [get_bd_pins adc12_cdc/m_axis_aclk] [get_bd_pins adc20_cdc/m_axis_aclk] [get_bd_pins adc22_cdc/m_axis_aclk] [get_bd_pins adc30_cdc/m_axis_aclk] [get_bd_pins adc32_cdc/m_axis_aclk]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set adc0_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 adc0_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {409600000.0} \
   ] $adc0_clk

  set adc1_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 adc1_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {409600000.0} \
   ] $adc1_clk

  set adc2_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 adc2_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {409600000.0} \
   ] $adc2_clk

  set adc3_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 adc3_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {409600000.0} \
   ] $adc3_clk

  set dac0_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 dac0_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {409600000.0} \
   ] $dac0_clk

  set dac1_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 dac1_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {409600000.0} \
   ] $dac1_clk

  set sysref_in [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_usp_rf_data_converter:diff_pins_rtl:1.0 sysref_in ]

  set vin0_01 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin0_01 ]

  set vin0_23 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin0_23 ]

  set vin1_01 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin1_01 ]

  set vin1_23 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin1_23 ]

  set vin2_01 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin2_01 ]

  set vin2_23 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin2_23 ]

  set vin3_01 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin3_01 ]

  set vin3_23 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vin3_23 ]

  set vout00 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout00 ]

  set vout01 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout01 ]

  set vout02 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout02 ]

  set vout03 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout03 ]

  set vout10 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout10 ]

  set vout11 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout11 ]

  set vout12 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout12 ]

  set vout13 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 vout13 ]


  # Create ports
  set ADCIO [ create_bd_port -dir I -from 19 -to 12 ADCIO ]
  set cs_n [ create_bd_port -dir O -from 7 -to 0 cs_n ]
  set sck [ create_bd_port -dir O -type data sck ]
  set sdi [ create_bd_port -dir O -type data sdi ]

  # Create instance: adc_cdc
  create_hier_cell_adc_cdc [current_bd_instance .] adc_cdc

  # Create instance: adc_clk_512, and set properties
  set adc_clk_512 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 adc_clk_512 ]
  set_property -dict [list \
    CONFIG.AUTO_PRIMITIVE {PLL} \
    CONFIG.CLKIN1_JITTER_PS {39.06} \
    CONFIG.CLKOUT1_DRIVES {Buffer} \
    CONFIG.CLKOUT1_JITTER {77.282} \
    CONFIG.CLKOUT1_PHASE_ERROR {84.800} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {512} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.CLKOUT5_DRIVES {Buffer} \
    CONFIG.CLKOUT6_DRIVES {Buffer} \
    CONFIG.CLKOUT7_DRIVES {Buffer} \
    CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {4} \
    CONFIG.MMCM_CLKIN1_PERIOD {3.906} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {2} \
    CONFIG.MMCM_COMPENSATION {AUTO} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true} \
    CONFIG.PRIMITIVE {Auto} \
    CONFIG.PRIM_IN_FREQ {256} \
    CONFIG.PRIM_SOURCE {Global_buffer} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
  ] $adc_clk_512


  # Create instance: adc_dma_cdc_fifo, and set properties
  set adc_dma_cdc_fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 adc_dma_cdc_fifo ]
  set_property -dict [list \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {4} \
  ] $adc_dma_cdc_fifo


  # Create instance: adc_mux_config
  create_hier_cell_adc_mux_config [current_bd_instance .] adc_mux_config

  # Create instance: adc_reset_256, and set properties
  set adc_reset_256 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 adc_reset_256 ]

  # Create instance: adc_reset_512, and set properties
  set adc_reset_512 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 adc_reset_512 ]

  # Create instance: awg_burst_length
  create_hier_cell_awg_burst_length [current_bd_instance .] awg_burst_length

  # Create instance: awg_dma_error
  create_hier_cell_awg_dma_error [current_bd_instance .] awg_dma_error

  # Create instance: awg_frame_depth
  create_hier_cell_awg_frame_depth [current_bd_instance .] awg_frame_depth

  # Create instance: awg_start_stop
  create_hier_cell_awg_start_stop [current_bd_instance .] awg_start_stop

  # Create instance: awg_trigger_out_config
  create_hier_cell_awg_trigger_out_config [current_bd_instance .] awg_trigger_out_config

  # Create instance: axi_dma_0, and set properties
  set axi_dma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0 ]
  set_property -dict [list \
    CONFIG.c_addr_width {48} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_s2mm_data_width {128} \
    CONFIG.c_m_axis_mm2s_tdata_width {128} \
    CONFIG.c_mm2s_burst_size {256} \
    CONFIG.c_s2mm_burst_size {256} \
    CONFIG.c_s_axis_s2mm_tdata_width {128} \
    CONFIG.c_sg_length_width {26} \
  ] $axi_dma_0


  # Create instance: axi_gpio_0, and set properties
  set axi_gpio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_GPIO_WIDTH {8} \
  ] $axi_gpio_0


  # Create instance: axi_smc, and set properties
  set axi_smc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc ]
  set_property CONFIG.NUM_SI {1} $axi_smc


  # Create instance: axi_smc_1, and set properties
  set axi_smc_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_1 ]
  set_property CONFIG.NUM_SI {1} $axi_smc_1


  # Create instance: buffer_config
  create_hier_cell_buffer_config [current_bd_instance .] buffer_config

  # Create instance: buffer_start_stop
  create_hier_cell_buffer_start_stop [current_bd_instance .] buffer_start_stop

  # Create instance: buffer_timestamp_width
  create_hier_cell_buffer_timestamp_width [current_bd_instance .] buffer_timestamp_width

  # Create instance: dac_mux_config
  create_hier_cell_dac_mux_config [current_bd_instance .] dac_mux_config

  # Create instance: dac_reset_384, and set properties
  set dac_reset_384 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 dac_reset_384 ]

  # Create instance: dac_scale_config
  create_hier_cell_dac_scale_config [current_bd_instance .] dac_scale_config

  # Create instance: daq_axis_0, and set properties
  set block_name daq_axis
  set block_cell_name daq_axis_0
  if { [catch {set daq_axis_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $daq_axis_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: dds_phase_inc
  create_hier_cell_dds_phase_inc [current_bd_instance .] dds_phase_inc

  # Create instance: lmh6401_config
  create_hier_cell_lmh6401_config [current_bd_instance .] lmh6401_config

  # Create instance: ps8_0_axi_periph, and set properties
  set ps8_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph ]
  set_property CONFIG.NUM_MI {1} $ps8_0_axi_periph


  # Create instance: ps8_0_axi_periph_1, and set properties
  set ps8_0_axi_periph_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph_1 ]
  set_property CONFIG.NUM_MI {17} $ps8_0_axi_periph_1


  # Create instance: ps_reset_100, and set properties
  set ps_reset_100 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 ps_reset_100 ]

  # Create instance: sample_discriminator_config
  create_hier_cell_sample_discriminator_config [current_bd_instance .] sample_discriminator_config

  # Create instance: trigger_manager_config
  create_hier_cell_trigger_manager_config [current_bd_instance .] trigger_manager_config

  # Create instance: usp_rf_data_converter_0, and set properties
  set usp_rf_data_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:usp_rf_data_converter:2.6 usp_rf_data_converter_0 ]
  set_property -dict [list \
    CONFIG.ADC0_Outclk_Freq {256.000} \
    CONFIG.ADC0_PLL_Enable {true} \
    CONFIG.ADC0_Refclk_Freq {409.600} \
    CONFIG.ADC0_Sampling_Rate {4.096} \
    CONFIG.ADC1_Outclk_Freq {32.000} \
    CONFIG.ADC1_PLL_Enable {true} \
    CONFIG.ADC1_Refclk_Freq {409.600} \
    CONFIG.ADC1_Sampling_Rate {4.096} \
    CONFIG.ADC2_Outclk_Freq {32.000} \
    CONFIG.ADC2_PLL_Enable {true} \
    CONFIG.ADC2_Refclk_Freq {409.600} \
    CONFIG.ADC2_Sampling_Rate {4.096} \
    CONFIG.ADC3_Outclk_Freq {32.000} \
    CONFIG.ADC3_PLL_Enable {true} \
    CONFIG.ADC3_Refclk_Freq {409.600} \
    CONFIG.ADC3_Sampling_Rate {4.096} \
    CONFIG.ADC_Slice02_Enable {true} \
    CONFIG.ADC_Slice10_Enable {true} \
    CONFIG.ADC_Slice12_Enable {true} \
    CONFIG.ADC_Slice20_Enable {true} \
    CONFIG.ADC_Slice22_Enable {true} \
    CONFIG.ADC_Slice30_Enable {true} \
    CONFIG.ADC_Slice32_Enable {true} \
    CONFIG.DAC0_PLL_Enable {true} \
    CONFIG.DAC0_Refclk_Freq {409.600} \
    CONFIG.DAC0_Sampling_Rate {6.144} \
    CONFIG.DAC1_Outclk_Freq {48.000} \
    CONFIG.DAC1_PLL_Enable {true} \
    CONFIG.DAC1_Refclk_Freq {409.600} \
    CONFIG.DAC1_Sampling_Rate {6.144} \
    CONFIG.DAC_Slice00_Enable {true} \
    CONFIG.DAC_Slice01_Enable {true} \
    CONFIG.DAC_Slice02_Enable {true} \
    CONFIG.DAC_Slice03_Enable {true} \
    CONFIG.DAC_Slice10_Enable {true} \
    CONFIG.DAC_Slice11_Enable {true} \
    CONFIG.DAC_Slice12_Enable {true} \
    CONFIG.DAC_Slice13_Enable {true} \
  ] $usp_rf_data_converter_0


  # Create instance: zynq_ultra_ps_e_0, and set properties
  set zynq_ultra_ps_e_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.4 zynq_ultra_ps_e_0 ]
  set_property -dict [list \
    CONFIG.PSU_BANK_0_IO_STANDARD {LVCMOS18} \
    CONFIG.PSU_BANK_1_IO_STANDARD {LVCMOS18} \
    CONFIG.PSU_BANK_2_IO_STANDARD {LVCMOS18} \
    CONFIG.PSU_DDR_RAM_HIGHADDR {0xFFFFFFFF} \
    CONFIG.PSU_DDR_RAM_HIGHADDR_OFFSET {0x800000000} \
    CONFIG.PSU_DDR_RAM_LOWADDR_OFFSET {0x80000000} \
    CONFIG.PSU_DYNAMIC_DDR_CONFIG_EN {1} \
    CONFIG.PSU_MIO_13_POLARITY {Default} \
    CONFIG.PSU_MIO_20_POLARITY {Default} \
    CONFIG.PSU_MIO_21_POLARITY {Default} \
    CONFIG.PSU_MIO_22_INPUT_TYPE {cmos} \
    CONFIG.PSU_MIO_22_POLARITY {Default} \
    CONFIG.PSU_MIO_23_POLARITY {Default} \
    CONFIG.PSU_MIO_24_POLARITY {Default} \
    CONFIG.PSU_MIO_25_POLARITY {Default} \
    CONFIG.PSU_MIO_26_POLARITY {Default} \
    CONFIG.PSU_MIO_31_POLARITY {Default} \
    CONFIG.PSU_MIO_38_POLARITY {Default} \
    CONFIG.PSU_MIO_43_POLARITY {Default} \
    CONFIG.PSU_MIO_44_POLARITY {Default} \
    CONFIG.PSU_MIO_TREE_PERIPHERALS {Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Feedback Clk#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad\
SPI Flash#Quad SPI Flash#GPIO0 MIO#I2C 0#I2C 0#I2C 1#I2C 1#UART 0#UART 0#GPIO0 MIO#GPIO0 MIO#GPIO0 MIO#GPIO0 MIO#GPIO0 MIO#GPIO0 MIO#GPIO1 MIO#DPAUX#DPAUX#DPAUX#DPAUX#GPIO1 MIO#PMU GPO 0#PMU GPO 1#PMU\
GPO 2#PMU GPO 3#PMU GPO 4#PMU GPO 5#GPIO1 MIO#SD 1#SD 1#SD 1#SD 1#GPIO1 MIO#GPIO1 MIO#SD 1#SD 1#SD 1#SD 1#SD 1#SD 1#SD 1#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#Gem 3#Gem\
3#Gem 3#Gem 3#Gem 3#Gem 3#Gem 3#Gem 3#Gem 3#Gem 3#Gem 3#Gem 3#MDIO 3#MDIO 3} \
    CONFIG.PSU_MIO_TREE_SIGNALS {sclk_out#miso_mo1#mo2#mo3#mosi_mi0#n_ss_out#clk_for_lpbk#n_ss_out_upper#mo_upper[0]#mo_upper[1]#mo_upper[2]#mo_upper[3]#sclk_out_upper#gpio0[13]#scl_out#sda_out#scl_out#sda_out#rxd#txd#gpio0[20]#gpio0[21]#gpio0[22]#gpio0[23]#gpio0[24]#gpio0[25]#gpio1[26]#dp_aux_data_out#dp_hot_plug_detect#dp_aux_data_oe#dp_aux_data_in#gpio1[31]#gpo[0]#gpo[1]#gpo[2]#gpo[3]#gpo[4]#gpo[5]#gpio1[38]#sdio1_data_out[4]#sdio1_data_out[5]#sdio1_data_out[6]#sdio1_data_out[7]#gpio1[43]#gpio1[44]#sdio1_cd_n#sdio1_data_out[0]#sdio1_data_out[1]#sdio1_data_out[2]#sdio1_data_out[3]#sdio1_cmd_out#sdio1_clk_out#ulpi_clk_in#ulpi_dir#ulpi_tx_data[2]#ulpi_nxt#ulpi_tx_data[0]#ulpi_tx_data[1]#ulpi_stp#ulpi_tx_data[3]#ulpi_tx_data[4]#ulpi_tx_data[5]#ulpi_tx_data[6]#ulpi_tx_data[7]#rgmii_tx_clk#rgmii_txd[0]#rgmii_txd[1]#rgmii_txd[2]#rgmii_txd[3]#rgmii_tx_ctl#rgmii_rx_clk#rgmii_rxd[0]#rgmii_rxd[1]#rgmii_rxd[2]#rgmii_rxd[3]#rgmii_rx_ctl#gem3_mdc#gem3_mdio_out}\
\
    CONFIG.PSU_SD1_INTERNAL_BUS_WIDTH {8} \
    CONFIG.PSU_USB3__DUAL_CLOCK_ENABLE {1} \
    CONFIG.PSU__ACT_DDR_FREQ_MHZ {1066.656006} \
    CONFIG.PSU__CAN1__PERIPHERAL__ENABLE {0} \
    CONFIG.PSU__CRF_APB__ACPU_CTRL__ACT_FREQMHZ {1199.988037} \
    CONFIG.PSU__CRF_APB__ACPU_CTRL__FREQMHZ {1200} \
    CONFIG.PSU__CRF_APB__ACPU_CTRL__SRCSEL {APLL} \
    CONFIG.PSU__CRF_APB__APLL_CTRL__SRCSEL {PSS_REF_CLK} \
    CONFIG.PSU__CRF_APB__DBG_FPD_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRF_APB__DBG_FPD_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRF_APB__DBG_FPD_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRF_APB__DBG_TRACE_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRF_APB__DBG_TRACE_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRF_APB__DBG_TSTMP_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRF_APB__DBG_TSTMP_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRF_APB__DBG_TSTMP_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRF_APB__DDR_CTRL__ACT_FREQMHZ {533.328003} \
    CONFIG.PSU__CRF_APB__DDR_CTRL__FREQMHZ {1067} \
    CONFIG.PSU__CRF_APB__DDR_CTRL__SRCSEL {DPLL} \
    CONFIG.PSU__CRF_APB__DPDMA_REF_CTRL__ACT_FREQMHZ {599.994019} \
    CONFIG.PSU__CRF_APB__DPDMA_REF_CTRL__FREQMHZ {600} \
    CONFIG.PSU__CRF_APB__DPDMA_REF_CTRL__SRCSEL {APLL} \
    CONFIG.PSU__CRF_APB__DPLL_CTRL__SRCSEL {PSS_REF_CLK} \
    CONFIG.PSU__CRF_APB__DP_AUDIO_REF_CTRL__ACT_FREQMHZ {24.999750} \
    CONFIG.PSU__CRF_APB__DP_AUDIO_REF_CTRL__SRCSEL {RPLL} \
    CONFIG.PSU__CRF_APB__DP_AUDIO__FRAC_ENABLED {0} \
    CONFIG.PSU__CRF_APB__DP_STC_REF_CTRL__ACT_FREQMHZ {26.785446} \
    CONFIG.PSU__CRF_APB__DP_STC_REF_CTRL__SRCSEL {RPLL} \
    CONFIG.PSU__CRF_APB__DP_VIDEO_REF_CTRL__ACT_FREQMHZ {299.997009} \
    CONFIG.PSU__CRF_APB__DP_VIDEO_REF_CTRL__SRCSEL {VPLL} \
    CONFIG.PSU__CRF_APB__DP_VIDEO__FRAC_ENABLED {0} \
    CONFIG.PSU__CRF_APB__GDMA_REF_CTRL__ACT_FREQMHZ {599.994019} \
    CONFIG.PSU__CRF_APB__GDMA_REF_CTRL__FREQMHZ {600} \
    CONFIG.PSU__CRF_APB__GDMA_REF_CTRL__SRCSEL {APLL} \
    CONFIG.PSU__CRF_APB__GPU_REF_CTRL__FREQMHZ {500} \
    CONFIG.PSU__CRF_APB__GPU_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRF_APB__SATA_REF_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRF_APB__SATA_REF_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRF_APB__SATA_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRF_APB__TOPSW_LSBUS_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRF_APB__TOPSW_LSBUS_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRF_APB__TOPSW_LSBUS_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRF_APB__TOPSW_MAIN_CTRL__ACT_FREQMHZ {533.328003} \
    CONFIG.PSU__CRF_APB__TOPSW_MAIN_CTRL__FREQMHZ {533.33} \
    CONFIG.PSU__CRF_APB__TOPSW_MAIN_CTRL__SRCSEL {DPLL} \
    CONFIG.PSU__CRF_APB__VPLL_CTRL__SRCSEL {PSS_REF_CLK} \
    CONFIG.PSU__CRL_APB__ADMA_REF_CTRL__ACT_FREQMHZ {499.994995} \
    CONFIG.PSU__CRL_APB__ADMA_REF_CTRL__FREQMHZ {500} \
    CONFIG.PSU__CRL_APB__ADMA_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__AMS_REF_CTRL__ACT_FREQMHZ {49.999500} \
    CONFIG.PSU__CRL_APB__CAN1_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__CAN1_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__CPU_R5_CTRL__ACT_FREQMHZ {499.994995} \
    CONFIG.PSU__CRL_APB__CPU_R5_CTRL__FREQMHZ {500} \
    CONFIG.PSU__CRL_APB__CPU_R5_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__DBG_LPD_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRL_APB__DBG_LPD_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRL_APB__DBG_LPD_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__DLL_REF_CTRL__ACT_FREQMHZ {1499.984985} \
    CONFIG.PSU__CRL_APB__GEM3_REF_CTRL__ACT_FREQMHZ {124.998749} \
    CONFIG.PSU__CRL_APB__GEM3_REF_CTRL__FREQMHZ {125} \
    CONFIG.PSU__CRL_APB__GEM3_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__GEM_TSU_REF_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRL_APB__GEM_TSU_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__I2C0_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__I2C0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__I2C0_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__I2C1_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__I2C1_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__I2C1_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__IOPLL_CTRL__SRCSEL {PSS_REF_CLK} \
    CONFIG.PSU__CRL_APB__IOU_SWITCH_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRL_APB__IOU_SWITCH_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRL_APB__IOU_SWITCH_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__LPD_LSBUS_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__LPD_LSBUS_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__LPD_LSBUS_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__LPD_SWITCH_CTRL__ACT_FREQMHZ {499.994995} \
    CONFIG.PSU__CRL_APB__LPD_SWITCH_CTRL__FREQMHZ {500} \
    CONFIG.PSU__CRL_APB__LPD_SWITCH_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__PCAP_CTRL__ACT_FREQMHZ {187.498123} \
    CONFIG.PSU__CRL_APB__PCAP_CTRL__FREQMHZ {200} \
    CONFIG.PSU__CRL_APB__PCAP_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__ACT_FREQMHZ {124.998749} \
    CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__FREQMHZ {125} \
    CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__RPLL_CTRL__SRCSEL {PSS_REF_CLK} \
    CONFIG.PSU__CRL_APB__SDIO1_REF_CTRL__ACT_FREQMHZ {187.498123} \
    CONFIG.PSU__CRL_APB__SDIO1_REF_CTRL__FREQMHZ {200} \
    CONFIG.PSU__CRL_APB__SDIO1_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__TIMESTAMP_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__TIMESTAMP_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__TIMESTAMP_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__UART0_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__UART0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__UART0_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__UART1_REF_CTRL__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__CRL_APB__UART1_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__CRL_APB__UART1_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__USB0_BUS_REF_CTRL__ACT_FREQMHZ {249.997498} \
    CONFIG.PSU__CRL_APB__USB0_BUS_REF_CTRL__FREQMHZ {250} \
    CONFIG.PSU__CRL_APB__USB0_BUS_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__USB3_DUAL_REF_CTRL__ACT_FREQMHZ {19.999800} \
    CONFIG.PSU__CRL_APB__USB3_DUAL_REF_CTRL__FREQMHZ {20} \
    CONFIG.PSU__CRL_APB__USB3_DUAL_REF_CTRL__SRCSEL {IOPLL} \
    CONFIG.PSU__CRL_APB__USB3__ENABLE {1} \
    CONFIG.PSU__CSUPMU__PERIPHERAL__VALID {1} \
    CONFIG.PSU__DDRC__BG_ADDR_COUNT {1} \
    CONFIG.PSU__DDRC__BRC_MAPPING {ROW_BANK_COL} \
    CONFIG.PSU__DDRC__BUS_WIDTH {64 Bit} \
    CONFIG.PSU__DDRC__CL {15} \
    CONFIG.PSU__DDRC__CLOCK_STOP_EN {0} \
    CONFIG.PSU__DDRC__COMPONENTS {UDIMM} \
    CONFIG.PSU__DDRC__CWL {14} \
    CONFIG.PSU__DDRC__DDR4_ADDR_MAPPING {0} \
    CONFIG.PSU__DDRC__DDR4_CAL_MODE_ENABLE {0} \
    CONFIG.PSU__DDRC__DDR4_CRC_CONTROL {0} \
    CONFIG.PSU__DDRC__DDR4_T_REF_MODE {0} \
    CONFIG.PSU__DDRC__DDR4_T_REF_RANGE {Normal (0-85)} \
    CONFIG.PSU__DDRC__DEVICE_CAPACITY {8192 MBits} \
    CONFIG.PSU__DDRC__DM_DBI {DM_NO_DBI} \
    CONFIG.PSU__DDRC__DRAM_WIDTH {16 Bits} \
    CONFIG.PSU__DDRC__ECC {Disabled} \
    CONFIG.PSU__DDRC__FGRM {1X} \
    CONFIG.PSU__DDRC__LP_ASR {manual normal} \
    CONFIG.PSU__DDRC__MEMORY_TYPE {DDR 4} \
    CONFIG.PSU__DDRC__PARITY_ENABLE {0} \
    CONFIG.PSU__DDRC__PER_BANK_REFRESH {0} \
    CONFIG.PSU__DDRC__PHY_DBI_MODE {0} \
    CONFIG.PSU__DDRC__RANK_ADDR_COUNT {0} \
    CONFIG.PSU__DDRC__ROW_ADDR_COUNT {16} \
    CONFIG.PSU__DDRC__SELF_REF_ABORT {0} \
    CONFIG.PSU__DDRC__SPEED_BIN {DDR4_2133P} \
    CONFIG.PSU__DDRC__STATIC_RD_MODE {0} \
    CONFIG.PSU__DDRC__TRAIN_DATA_EYE {1} \
    CONFIG.PSU__DDRC__TRAIN_READ_GATE {1} \
    CONFIG.PSU__DDRC__TRAIN_WRITE_LEVEL {1} \
    CONFIG.PSU__DDRC__T_FAW {30.0} \
    CONFIG.PSU__DDRC__T_RAS_MIN {33} \
    CONFIG.PSU__DDRC__T_RC {47.06} \
    CONFIG.PSU__DDRC__T_RCD {15} \
    CONFIG.PSU__DDRC__T_RP {15} \
    CONFIG.PSU__DDRC__VREF {1} \
    CONFIG.PSU__DDR_HIGH_ADDRESS_GUI_ENABLE {1} \
    CONFIG.PSU__DDR__INTERFACE__FREQMHZ {533.500} \
    CONFIG.PSU__DISPLAYPORT__LANE0__ENABLE {1} \
    CONFIG.PSU__DISPLAYPORT__LANE0__IO {GT Lane1} \
    CONFIG.PSU__DISPLAYPORT__LANE1__ENABLE {1} \
    CONFIG.PSU__DISPLAYPORT__LANE1__IO {GT Lane0} \
    CONFIG.PSU__DISPLAYPORT__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__DLL__ISUSED {1} \
    CONFIG.PSU__DPAUX__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__DPAUX__PERIPHERAL__IO {MIO 27 .. 30} \
    CONFIG.PSU__DP__LANE_SEL {Dual Lower} \
    CONFIG.PSU__DP__REF_CLK_FREQ {27} \
    CONFIG.PSU__DP__REF_CLK_SEL {Ref Clk1} \
    CONFIG.PSU__ENET3__FIFO__ENABLE {0} \
    CONFIG.PSU__ENET3__GRP_MDIO__ENABLE {1} \
    CONFIG.PSU__ENET3__GRP_MDIO__IO {MIO 76 .. 77} \
    CONFIG.PSU__ENET3__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__ENET3__PERIPHERAL__IO {MIO 64 .. 75} \
    CONFIG.PSU__ENET3__PTP__ENABLE {0} \
    CONFIG.PSU__ENET3__TSU__ENABLE {0} \
    CONFIG.PSU__FPDMASTERS_COHERENCY {0} \
    CONFIG.PSU__FPD_SLCR__WDT1__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__GEM3_COHERENCY {0} \
    CONFIG.PSU__GEM3_ROUTE_THROUGH_FPD {0} \
    CONFIG.PSU__GEM__TSU__ENABLE {0} \
    CONFIG.PSU__GPIO0_MIO__IO {MIO 0 .. 25} \
    CONFIG.PSU__GPIO0_MIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__GPIO1_MIO__IO {MIO 26 .. 51} \
    CONFIG.PSU__GPIO1_MIO__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__GT__LINK_SPEED {HBR} \
    CONFIG.PSU__GT__PRE_EMPH_LVL_4 {0} \
    CONFIG.PSU__GT__VLT_SWNG_LVL_4 {0} \
    CONFIG.PSU__I2C0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__I2C0__PERIPHERAL__IO {MIO 14 .. 15} \
    CONFIG.PSU__I2C1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__I2C1__PERIPHERAL__IO {MIO 16 .. 17} \
    CONFIG.PSU__IOU_SLCR__IOU_TTC_APB_CLK__TTC0_SEL {APB} \
    CONFIG.PSU__IOU_SLCR__IOU_TTC_APB_CLK__TTC1_SEL {APB} \
    CONFIG.PSU__IOU_SLCR__IOU_TTC_APB_CLK__TTC2_SEL {APB} \
    CONFIG.PSU__IOU_SLCR__IOU_TTC_APB_CLK__TTC3_SEL {APB} \
    CONFIG.PSU__IOU_SLCR__TTC0__ACT_FREQMHZ {100.000000} \
    CONFIG.PSU__IOU_SLCR__TTC1__ACT_FREQMHZ {100.000000} \
    CONFIG.PSU__IOU_SLCR__TTC2__ACT_FREQMHZ {100.000000} \
    CONFIG.PSU__IOU_SLCR__TTC3__ACT_FREQMHZ {100.000000} \
    CONFIG.PSU__IOU_SLCR__WDT0__ACT_FREQMHZ {99.999001} \
    CONFIG.PSU__LPD_SLCR__CSUPMU__ACT_FREQMHZ {100.000000} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {128} \
    CONFIG.PSU__MAXIGP1__DATA_WIDTH {128} \
    CONFIG.PSU__OVERRIDE__BASIC_CLOCK {0} \
    CONFIG.PSU__PL_CLK0_BUF {TRUE} \
    CONFIG.PSU__PMU_COHERENCY {0} \
    CONFIG.PSU__PMU__AIBACK__ENABLE {0} \
    CONFIG.PSU__PMU__EMIO_GPI__ENABLE {0} \
    CONFIG.PSU__PMU__EMIO_GPO__ENABLE {0} \
    CONFIG.PSU__PMU__GPI0__ENABLE {0} \
    CONFIG.PSU__PMU__GPI1__ENABLE {0} \
    CONFIG.PSU__PMU__GPI2__ENABLE {0} \
    CONFIG.PSU__PMU__GPI3__ENABLE {0} \
    CONFIG.PSU__PMU__GPI4__ENABLE {0} \
    CONFIG.PSU__PMU__GPI5__ENABLE {0} \
    CONFIG.PSU__PMU__GPO0__ENABLE {1} \
    CONFIG.PSU__PMU__GPO0__IO {MIO 32} \
    CONFIG.PSU__PMU__GPO1__ENABLE {1} \
    CONFIG.PSU__PMU__GPO1__IO {MIO 33} \
    CONFIG.PSU__PMU__GPO2__ENABLE {1} \
    CONFIG.PSU__PMU__GPO2__IO {MIO 34} \
    CONFIG.PSU__PMU__GPO2__POLARITY {low} \
    CONFIG.PSU__PMU__GPO3__ENABLE {1} \
    CONFIG.PSU__PMU__GPO3__IO {MIO 35} \
    CONFIG.PSU__PMU__GPO3__POLARITY {low} \
    CONFIG.PSU__PMU__GPO4__ENABLE {1} \
    CONFIG.PSU__PMU__GPO4__IO {MIO 36} \
    CONFIG.PSU__PMU__GPO4__POLARITY {low} \
    CONFIG.PSU__PMU__GPO5__ENABLE {1} \
    CONFIG.PSU__PMU__GPO5__IO {MIO 37} \
    CONFIG.PSU__PMU__GPO5__POLARITY {low} \
    CONFIG.PSU__PMU__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__PMU__PLERROR__ENABLE {0} \
    CONFIG.PSU__PRESET_APPLIED {1} \
    CONFIG.PSU__PROTECTION__MASTERS {USB1:NonSecure;0|USB0:NonSecure;1|S_AXI_LPD:NA;0|S_AXI_HPC1_FPD:NA;0|S_AXI_HPC0_FPD:NA;0|S_AXI_HP3_FPD:NA;0|S_AXI_HP2_FPD:NA;1|S_AXI_HP1_FPD:NA;0|S_AXI_HP0_FPD:NA;1|S_AXI_ACP:NA;0|S_AXI_ACE:NA;0|SD1:NonSecure;1|SD0:NonSecure;0|SATA1:NonSecure;1|SATA0:NonSecure;1|RPU1:Secure;1|RPU0:Secure;1|QSPI:NonSecure;1|PMU:NA;1|PCIe:NonSecure;0|NAND:NonSecure;0|LDMA:NonSecure;1|GPU:NonSecure;1|GEM3:NonSecure;1|GEM2:NonSecure;0|GEM1:NonSecure;0|GEM0:NonSecure;0|FDMA:NonSecure;1|DP:NonSecure;1|DAP:NA;1|Coresight:NA;1|CSU:NA;1|APU:NA;1}\
\
    CONFIG.PSU__PROTECTION__SLAVES {LPD;USB3_1_XHCI;FE300000;FE3FFFFF;0|LPD;USB3_1;FF9E0000;FF9EFFFF;0|LPD;USB3_0_XHCI;FE200000;FE2FFFFF;1|LPD;USB3_0;FF9D0000;FF9DFFFF;1|LPD;UART1;FF010000;FF01FFFF;1|LPD;UART0;FF000000;FF00FFFF;1|LPD;TTC3;FF140000;FF14FFFF;1|LPD;TTC2;FF130000;FF13FFFF;1|LPD;TTC1;FF120000;FF12FFFF;1|LPD;TTC0;FF110000;FF11FFFF;1|FPD;SWDT1;FD4D0000;FD4DFFFF;1|LPD;SWDT0;FF150000;FF15FFFF;1|LPD;SPI1;FF050000;FF05FFFF;0|LPD;SPI0;FF040000;FF04FFFF;0|FPD;SMMU_REG;FD5F0000;FD5FFFFF;1|FPD;SMMU;FD800000;FDFFFFFF;1|FPD;SIOU;FD3D0000;FD3DFFFF;1|FPD;SERDES;FD400000;FD47FFFF;1|LPD;SD1;FF170000;FF17FFFF;1|LPD;SD0;FF160000;FF16FFFF;0|FPD;SATA;FD0C0000;FD0CFFFF;1|LPD;RTC;FFA60000;FFA6FFFF;1|LPD;RSA_CORE;FFCE0000;FFCEFFFF;1|LPD;RPU;FF9A0000;FF9AFFFF;1|LPD;R5_TCM_RAM_GLOBAL;FFE00000;FFE3FFFF;1|LPD;R5_1_Instruction_Cache;FFEC0000;FFECFFFF;1|LPD;R5_1_Data_Cache;FFED0000;FFEDFFFF;1|LPD;R5_1_BTCM_GLOBAL;FFEB0000;FFEBFFFF;1|LPD;R5_1_ATCM_GLOBAL;FFE90000;FFE9FFFF;1|LPD;R5_0_Instruction_Cache;FFE40000;FFE4FFFF;1|LPD;R5_0_Data_Cache;FFE50000;FFE5FFFF;1|LPD;R5_0_BTCM_GLOBAL;FFE20000;FFE2FFFF;1|LPD;R5_0_ATCM_GLOBAL;FFE00000;FFE0FFFF;1|LPD;QSPI_Linear_Address;C0000000;DFFFFFFF;1|LPD;QSPI;FF0F0000;FF0FFFFF;1|LPD;PMU_RAM;FFDC0000;FFDDFFFF;1|LPD;PMU_GLOBAL;FFD80000;FFDBFFFF;1|FPD;PCIE_MAIN;FD0E0000;FD0EFFFF;0|FPD;PCIE_LOW;E0000000;EFFFFFFF;0|FPD;PCIE_HIGH2;8000000000;BFFFFFFFFF;0|FPD;PCIE_HIGH1;600000000;7FFFFFFFF;0|FPD;PCIE_DMA;FD0F0000;FD0FFFFF;0|FPD;PCIE_ATTRIB;FD480000;FD48FFFF;0|LPD;OCM_XMPU_CFG;FFA70000;FFA7FFFF;1|LPD;OCM_SLCR;FF960000;FF96FFFF;1|OCM;OCM;FFFC0000;FFFFFFFF;1|LPD;NAND;FF100000;FF10FFFF;0|LPD;MBISTJTAG;FFCF0000;FFCFFFFF;1|LPD;LPD_XPPU_SINK;FF9C0000;FF9CFFFF;1|LPD;LPD_XPPU;FF980000;FF98FFFF;1|LPD;LPD_SLCR_SECURE;FF4B0000;FF4DFFFF;1|LPD;LPD_SLCR;FF410000;FF4AFFFF;1|LPD;LPD_GPV;FE100000;FE1FFFFF;1|LPD;LPD_DMA_7;FFAF0000;FFAFFFFF;1|LPD;LPD_DMA_6;FFAE0000;FFAEFFFF;1|LPD;LPD_DMA_5;FFAD0000;FFADFFFF;1|LPD;LPD_DMA_4;FFAC0000;FFACFFFF;1|LPD;LPD_DMA_3;FFAB0000;FFABFFFF;1|LPD;LPD_DMA_2;FFAA0000;FFAAFFFF;1|LPD;LPD_DMA_1;FFA90000;FFA9FFFF;1|LPD;LPD_DMA_0;FFA80000;FFA8FFFF;1|LPD;IPI_CTRL;FF380000;FF3FFFFF;1|LPD;IOU_SLCR;FF180000;FF23FFFF;1|LPD;IOU_SECURE_SLCR;FF240000;FF24FFFF;1|LPD;IOU_SCNTRS;FF260000;FF26FFFF;1|LPD;IOU_SCNTR;FF250000;FF25FFFF;1|LPD;IOU_GPV;FE000000;FE0FFFFF;1|LPD;I2C1;FF030000;FF03FFFF;1|LPD;I2C0;FF020000;FF02FFFF;1|FPD;GPU;FD4B0000;FD4BFFFF;0|LPD;GPIO;FF0A0000;FF0AFFFF;1|LPD;GEM3;FF0E0000;FF0EFFFF;1|LPD;GEM2;FF0D0000;FF0DFFFF;0|LPD;GEM1;FF0C0000;FF0CFFFF;0|LPD;GEM0;FF0B0000;FF0BFFFF;0|FPD;FPD_XMPU_SINK;FD4F0000;FD4FFFFF;1|FPD;FPD_XMPU_CFG;FD5D0000;FD5DFFFF;1|FPD;FPD_SLCR_SECURE;FD690000;FD6CFFFF;1|FPD;FPD_SLCR;FD610000;FD68FFFF;1|FPD;FPD_DMA_CH7;FD570000;FD57FFFF;1|FPD;FPD_DMA_CH6;FD560000;FD56FFFF;1|FPD;FPD_DMA_CH5;FD550000;FD55FFFF;1|FPD;FPD_DMA_CH4;FD540000;FD54FFFF;1|FPD;FPD_DMA_CH3;FD530000;FD53FFFF;1|FPD;FPD_DMA_CH2;FD520000;FD52FFFF;1|FPD;FPD_DMA_CH1;FD510000;FD51FFFF;1|FPD;FPD_DMA_CH0;FD500000;FD50FFFF;1|LPD;EFUSE;FFCC0000;FFCCFFFF;1|FPD;Display\
Port;FD4A0000;FD4AFFFF;1|FPD;DPDMA;FD4C0000;FD4CFFFF;1|FPD;DDR_XMPU5_CFG;FD050000;FD05FFFF;1|FPD;DDR_XMPU4_CFG;FD040000;FD04FFFF;1|FPD;DDR_XMPU3_CFG;FD030000;FD03FFFF;1|FPD;DDR_XMPU2_CFG;FD020000;FD02FFFF;1|FPD;DDR_XMPU1_CFG;FD010000;FD01FFFF;1|FPD;DDR_XMPU0_CFG;FD000000;FD00FFFF;1|FPD;DDR_QOS_CTRL;FD090000;FD09FFFF;1|FPD;DDR_PHY;FD080000;FD08FFFF;1|DDR;DDR_LOW;0;7FFFFFFF;1|DDR;DDR_HIGH;800000000;87FFFFFFF;1|FPD;DDDR_CTRL;FD070000;FD070FFF;1|LPD;Coresight;FE800000;FEFFFFFF;1|LPD;CSU_DMA;FFC80000;FFC9FFFF;1|LPD;CSU;FFCA0000;FFCAFFFF;1|LPD;CRL_APB;FF5E0000;FF85FFFF;1|FPD;CRF_APB;FD1A0000;FD2DFFFF;1|FPD;CCI_REG;FD5E0000;FD5EFFFF;1|LPD;CAN1;FF070000;FF07FFFF;0|LPD;CAN0;FF060000;FF06FFFF;0|FPD;APU;FD5C0000;FD5CFFFF;1|LPD;APM_INTC_IOU;FFA20000;FFA2FFFF;1|LPD;APM_FPD_LPD;FFA30000;FFA3FFFF;1|FPD;APM_5;FD490000;FD49FFFF;1|FPD;APM_0;FD0B0000;FD0BFFFF;1|LPD;APM2;FFA10000;FFA1FFFF;1|LPD;APM1;FFA00000;FFA0FFFF;1|LPD;AMS;FFA50000;FFA5FFFF;1|FPD;AFI_5;FD3B0000;FD3BFFFF;1|FPD;AFI_4;FD3A0000;FD3AFFFF;1|FPD;AFI_3;FD390000;FD39FFFF;1|FPD;AFI_2;FD380000;FD38FFFF;1|FPD;AFI_1;FD370000;FD37FFFF;1|FPD;AFI_0;FD360000;FD36FFFF;1|LPD;AFIFM6;FF9B0000;FF9BFFFF;1|FPD;ACPU_GIC;F9010000;F907FFFF;1}\
\
    CONFIG.PSU__PSS_REF_CLK__FREQMHZ {33.333} \
    CONFIG.PSU__QSPI_COHERENCY {0} \
    CONFIG.PSU__QSPI_ROUTE_THROUGH_FPD {0} \
    CONFIG.PSU__QSPI__GRP_FBCLK__ENABLE {1} \
    CONFIG.PSU__QSPI__GRP_FBCLK__IO {MIO 6} \
    CONFIG.PSU__QSPI__PERIPHERAL__DATA_MODE {x4} \
    CONFIG.PSU__QSPI__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__QSPI__PERIPHERAL__IO {MIO 0 .. 12} \
    CONFIG.PSU__QSPI__PERIPHERAL__MODE {Dual Parallel} \
    CONFIG.PSU__SATA__LANE0__ENABLE {0} \
    CONFIG.PSU__SATA__LANE1__IO {GT Lane3} \
    CONFIG.PSU__SATA__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__SATA__REF_CLK_FREQ {125} \
    CONFIG.PSU__SATA__REF_CLK_SEL {Ref Clk3} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__SAXIGP4__DATA_WIDTH {128} \
    CONFIG.PSU__SD1_COHERENCY {0} \
    CONFIG.PSU__SD1_ROUTE_THROUGH_FPD {0} \
    CONFIG.PSU__SD1__CLK_100_SDR_OTAP_DLY {0x3} \
    CONFIG.PSU__SD1__CLK_200_SDR_OTAP_DLY {0x3} \
    CONFIG.PSU__SD1__CLK_50_DDR_ITAP_DLY {0x3D} \
    CONFIG.PSU__SD1__CLK_50_DDR_OTAP_DLY {0x4} \
    CONFIG.PSU__SD1__CLK_50_SDR_ITAP_DLY {0x15} \
    CONFIG.PSU__SD1__CLK_50_SDR_OTAP_DLY {0x5} \
    CONFIG.PSU__SD1__DATA_TRANSFER_MODE {8Bit} \
    CONFIG.PSU__SD1__GRP_CD__ENABLE {1} \
    CONFIG.PSU__SD1__GRP_CD__IO {MIO 45} \
    CONFIG.PSU__SD1__GRP_POW__ENABLE {0} \
    CONFIG.PSU__SD1__GRP_WP__ENABLE {0} \
    CONFIG.PSU__SD1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__SD1__PERIPHERAL__IO {MIO 39 .. 51} \
    CONFIG.PSU__SD1__SLOT_TYPE {SD 3.0} \
    CONFIG.PSU__SWDT0__CLOCK__ENABLE {0} \
    CONFIG.PSU__SWDT0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__SWDT0__RESET__ENABLE {0} \
    CONFIG.PSU__SWDT1__CLOCK__ENABLE {0} \
    CONFIG.PSU__SWDT1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__SWDT1__RESET__ENABLE {0} \
    CONFIG.PSU__TSU__BUFG_PORT_PAIR {0} \
    CONFIG.PSU__TTC0__CLOCK__ENABLE {0} \
    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {0} \
    CONFIG.PSU__TTC1__CLOCK__ENABLE {0} \
    CONFIG.PSU__TTC1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__TTC1__WAVEOUT__ENABLE {0} \
    CONFIG.PSU__TTC2__CLOCK__ENABLE {0} \
    CONFIG.PSU__TTC2__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__TTC2__WAVEOUT__ENABLE {0} \
    CONFIG.PSU__TTC3__CLOCK__ENABLE {0} \
    CONFIG.PSU__TTC3__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__TTC3__WAVEOUT__ENABLE {0} \
    CONFIG.PSU__UART0__BAUD_RATE {115200} \
    CONFIG.PSU__UART0__MODEM__ENABLE {0} \
    CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART0__PERIPHERAL__IO {MIO 18 .. 19} \
    CONFIG.PSU__UART1__BAUD_RATE {115200} \
    CONFIG.PSU__UART1__MODEM__ENABLE {0} \
    CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__UART1__PERIPHERAL__IO {EMIO} \
    CONFIG.PSU__USB0_COHERENCY {0} \
    CONFIG.PSU__USB0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__USB0__PERIPHERAL__IO {MIO 52 .. 63} \
    CONFIG.PSU__USB0__REF_CLK_FREQ {26} \
    CONFIG.PSU__USB0__REF_CLK_SEL {Ref Clk2} \
    CONFIG.PSU__USB2_0__EMIO__ENABLE {0} \
    CONFIG.PSU__USB3_0__EMIO__ENABLE {0} \
    CONFIG.PSU__USB3_0__PERIPHERAL__ENABLE {1} \
    CONFIG.PSU__USB3_0__PERIPHERAL__IO {GT Lane2} \
    CONFIG.PSU__USB__RESET__MODE {Boot Pin} \
    CONFIG.PSU__USB__RESET__POLARITY {Active Low} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {1} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__USE__S_AXI_GP4 {1} \
  ] $zynq_ultra_ps_e_0


  # Create interface connections
  connect_bd_intf_net -intf_net AXI_STR_RXD_1 [get_bd_intf_pins awg_dma_error/AXI_STR_RXD] [get_bd_intf_pins daq_axis_0/m_axis_awg_dma_error]
  connect_bd_intf_net -intf_net adc0_clk_1 [get_bd_intf_ports adc0_clk] [get_bd_intf_pins usp_rf_data_converter_0/adc0_clk]
  connect_bd_intf_net -intf_net adc10_cdc_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_10] [get_bd_intf_pins daq_axis_0/s10_axis_adc]
  connect_bd_intf_net -intf_net adc12_cdc_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_12] [get_bd_intf_pins daq_axis_0/s12_axis_adc]
  connect_bd_intf_net -intf_net adc1_clk_1 [get_bd_intf_ports adc1_clk] [get_bd_intf_pins usp_rf_data_converter_0/adc1_clk]
  connect_bd_intf_net -intf_net adc20_cdc_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_20] [get_bd_intf_pins daq_axis_0/s20_axis_adc]
  connect_bd_intf_net -intf_net adc22_cdc_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_22] [get_bd_intf_pins daq_axis_0/s22_axis_adc]
  connect_bd_intf_net -intf_net adc2_clk_1 [get_bd_intf_ports adc2_clk] [get_bd_intf_pins usp_rf_data_converter_0/adc2_clk]
  connect_bd_intf_net -intf_net adc30_cdc_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_30] [get_bd_intf_pins daq_axis_0/s30_axis_adc]
  connect_bd_intf_net -intf_net adc32_cdc_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_32] [get_bd_intf_pins daq_axis_0/s32_axis_adc]
  connect_bd_intf_net -intf_net adc3_clk_1 [get_bd_intf_ports adc3_clk] [get_bd_intf_pins usp_rf_data_converter_0/adc3_clk]
  connect_bd_intf_net -intf_net adc_dma_cdc_fifo_M_AXIS [get_bd_intf_pins adc_dma_cdc_fifo/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net adc_mux_config_M_AXIS [get_bd_intf_pins adc_mux_config/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_adc_mux_config]
  connect_bd_intf_net -intf_net awg_burst_length_M_AXIS [get_bd_intf_pins awg_burst_length/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_awg_burst_length]
  connect_bd_intf_net -intf_net awg_frame_depth_M_AXIS [get_bd_intf_pins awg_frame_depth/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_awg_frame_depth]
  connect_bd_intf_net -intf_net awg_start_stop_M_AXIS [get_bd_intf_pins awg_start_stop/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_awg_start_stop]
  connect_bd_intf_net -intf_net awg_trigger_out_config_M_AXIS [get_bd_intf_pins awg_trigger_out_config/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_awg_trigger_out_config]
  connect_bd_intf_net -intf_net axi_dma_0_M_AXIS_MM2S [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins daq_axis_0/s_axis_dma]
  connect_bd_intf_net -intf_net axi_dma_0_M_AXI_MM2S [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_smc/S00_AXI]
  connect_bd_intf_net -intf_net axi_dma_0_M_AXI_S2MM [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_smc_1/S00_AXI]
  connect_bd_intf_net -intf_net axi_smc_1_M00_AXI [get_bd_intf_pins axi_smc_1/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP2_FPD]
  connect_bd_intf_net -intf_net axi_smc_M00_AXI [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]
  connect_bd_intf_net -intf_net axis_data_fifo_0_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_00] [get_bd_intf_pins daq_axis_0/s00_axis_adc]
  connect_bd_intf_net -intf_net axis_data_fifo_1_M_AXIS [get_bd_intf_pins adc_cdc/M_AXIS_02] [get_bd_intf_pins daq_axis_0/s02_axis_adc]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins daq_axis_0/s_axis_sample_discriminator_config] [get_bd_intf_pins sample_discriminator_config/M_AXIS]
  connect_bd_intf_net -intf_net buffer_config_M_AXIS [get_bd_intf_pins buffer_config/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_buffer_config]
  connect_bd_intf_net -intf_net buffer_start_stop_M_AXIS [get_bd_intf_pins buffer_start_stop/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_buffer_start_stop]
  connect_bd_intf_net -intf_net dac0_clk_1 [get_bd_intf_ports dac0_clk] [get_bd_intf_pins usp_rf_data_converter_0/dac0_clk]
  connect_bd_intf_net -intf_net dac1_clk_1 [get_bd_intf_ports dac1_clk] [get_bd_intf_pins usp_rf_data_converter_0/dac1_clk]
  connect_bd_intf_net -intf_net dac_mux_config_M_AXIS [get_bd_intf_pins dac_mux_config/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_dac_mux_config]
  connect_bd_intf_net -intf_net dac_scale_config_M_AXIS [get_bd_intf_pins dac_scale_config/M_AXIS] [get_bd_intf_pins daq_axis_0/s_axis_dac_scale_config]
  connect_bd_intf_net -intf_net daq_axis_0_m00_axis_dac [get_bd_intf_pins daq_axis_0/m00_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s00_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m01_axis_dac [get_bd_intf_pins daq_axis_0/m01_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s01_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m02_axis_dac [get_bd_intf_pins daq_axis_0/m02_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s02_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m03_axis_dac [get_bd_intf_pins daq_axis_0/m03_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s03_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m10_axis_dac [get_bd_intf_pins daq_axis_0/m10_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s10_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m11_axis_dac [get_bd_intf_pins daq_axis_0/m11_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s11_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m12_axis_dac [get_bd_intf_pins daq_axis_0/m12_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s12_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m13_axis_dac [get_bd_intf_pins daq_axis_0/m13_axis_dac] [get_bd_intf_pins usp_rf_data_converter_0/s13_axis]
  connect_bd_intf_net -intf_net daq_axis_0_m_axis_buffer_timestamp_width [get_bd_intf_pins buffer_timestamp_width/AXI_STR_RXD] [get_bd_intf_pins daq_axis_0/m_axis_buffer_timestamp_width]
  connect_bd_intf_net -intf_net daq_axis_0_m_axis_dma [get_bd_intf_pins adc_dma_cdc_fifo/S_AXIS] [get_bd_intf_pins daq_axis_0/m_axis_dma]
  connect_bd_intf_net -intf_net dds_phase_inc_M_AXIS [get_bd_intf_pins daq_axis_0/s_axis_dds_phase_inc] [get_bd_intf_pins dds_phase_inc/M_AXIS]
  connect_bd_intf_net -intf_net lmh6401_config_M_AXIS [get_bd_intf_pins daq_axis_0/s_axis_lmh6401_config] [get_bd_intf_pins lmh6401_config/M_AXIS]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M00_AXI [get_bd_intf_pins ps8_0_axi_periph_1/M00_AXI] [get_bd_intf_pins usp_rf_data_converter_0/s_axi]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M01_AXI [get_bd_intf_pins ps8_0_axi_periph_1/M01_AXI] [get_bd_intf_pins sample_discriminator_config/S_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M02_AXI [get_bd_intf_pins buffer_config/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M02_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M03_AXI [get_bd_intf_pins adc_mux_config/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M03_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M04_AXI [get_bd_intf_pins buffer_start_stop/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M04_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M05_AXI [get_bd_intf_pins awg_frame_depth/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M05_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M06_AXI [get_bd_intf_pins awg_burst_length/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M06_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M07_AXI [get_bd_intf_pins awg_start_stop/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M07_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M08_AXI [get_bd_intf_pins awg_trigger_out_config/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M08_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M09_AXI [get_bd_intf_pins dac_mux_config/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M09_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M10_AXI [get_bd_intf_pins ps8_0_axi_periph_1/M10_AXI] [get_bd_intf_pins trigger_manager_config/S_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M11_AXI [get_bd_intf_pins dac_scale_config/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M11_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M12_AXI [get_bd_intf_pins dds_phase_inc/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M12_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M13_AXI [get_bd_intf_pins awg_dma_error/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M13_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M14_AXI [get_bd_intf_pins buffer_timestamp_width/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M14_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M15_AXI [get_bd_intf_pins axi_gpio_0/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M15_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_1_M16_AXI [get_bd_intf_pins lmh6401_config/S_AXI] [get_bd_intf_pins ps8_0_axi_periph_1/M16_AXI]
  connect_bd_intf_net -intf_net ps8_0_axi_periph_M00_AXI [get_bd_intf_pins axi_dma_0/S_AXI_LITE] [get_bd_intf_pins ps8_0_axi_periph/M00_AXI]
  connect_bd_intf_net -intf_net sysref_in_1 [get_bd_intf_ports sysref_in] [get_bd_intf_pins usp_rf_data_converter_0/sysref_in]
  connect_bd_intf_net -intf_net trigger_manager_config_M_AXIS [get_bd_intf_pins daq_axis_0/s_axis_trigger_manager_config] [get_bd_intf_pins trigger_manager_config/M_AXIS]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m00_axis [get_bd_intf_pins adc_cdc/S_AXIS_00] [get_bd_intf_pins usp_rf_data_converter_0/m00_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m02_axis [get_bd_intf_pins adc_cdc/S_AXIS_02] [get_bd_intf_pins usp_rf_data_converter_0/m02_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m10_axis [get_bd_intf_pins adc_cdc/S_AXIS_10] [get_bd_intf_pins usp_rf_data_converter_0/m10_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m12_axis [get_bd_intf_pins adc_cdc/S_AXIS_12] [get_bd_intf_pins usp_rf_data_converter_0/m12_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m20_axis [get_bd_intf_pins adc_cdc/S_AXIS_20] [get_bd_intf_pins usp_rf_data_converter_0/m20_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m22_axis [get_bd_intf_pins adc_cdc/S_AXIS_22] [get_bd_intf_pins usp_rf_data_converter_0/m22_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m30_axis [get_bd_intf_pins adc_cdc/S_AXIS_30] [get_bd_intf_pins usp_rf_data_converter_0/m30_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_m32_axis [get_bd_intf_pins adc_cdc/S_AXIS_32] [get_bd_intf_pins usp_rf_data_converter_0/m32_axis]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout00 [get_bd_intf_ports vout00] [get_bd_intf_pins usp_rf_data_converter_0/vout00]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout01 [get_bd_intf_ports vout01] [get_bd_intf_pins usp_rf_data_converter_0/vout01]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout02 [get_bd_intf_ports vout02] [get_bd_intf_pins usp_rf_data_converter_0/vout02]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout03 [get_bd_intf_ports vout03] [get_bd_intf_pins usp_rf_data_converter_0/vout03]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout10 [get_bd_intf_ports vout10] [get_bd_intf_pins usp_rf_data_converter_0/vout10]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout11 [get_bd_intf_ports vout11] [get_bd_intf_pins usp_rf_data_converter_0/vout11]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout12 [get_bd_intf_ports vout12] [get_bd_intf_pins usp_rf_data_converter_0/vout12]
  connect_bd_intf_net -intf_net usp_rf_data_converter_0_vout13 [get_bd_intf_ports vout13] [get_bd_intf_pins usp_rf_data_converter_0/vout13]
  connect_bd_intf_net -intf_net vin0_01_1 [get_bd_intf_ports vin0_01] [get_bd_intf_pins usp_rf_data_converter_0/vin0_01]
  connect_bd_intf_net -intf_net vin0_23_1 [get_bd_intf_ports vin0_23] [get_bd_intf_pins usp_rf_data_converter_0/vin0_23]
  connect_bd_intf_net -intf_net vin1_01_1 [get_bd_intf_ports vin1_01] [get_bd_intf_pins usp_rf_data_converter_0/vin1_01]
  connect_bd_intf_net -intf_net vin1_23_1 [get_bd_intf_ports vin1_23] [get_bd_intf_pins usp_rf_data_converter_0/vin1_23]
  connect_bd_intf_net -intf_net vin2_01_1 [get_bd_intf_ports vin2_01] [get_bd_intf_pins usp_rf_data_converter_0/vin2_01]
  connect_bd_intf_net -intf_net vin2_23_1 [get_bd_intf_ports vin2_23] [get_bd_intf_pins usp_rf_data_converter_0/vin2_23]
  connect_bd_intf_net -intf_net vin3_01_1 [get_bd_intf_ports vin3_01] [get_bd_intf_pins usp_rf_data_converter_0/vin3_01]
  connect_bd_intf_net -intf_net vin3_23_1 [get_bd_intf_ports vin3_23] [get_bd_intf_pins usp_rf_data_converter_0/vin3_23]
  connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_M_AXI_HPM0_FPD [get_bd_intf_pins ps8_0_axi_periph/S00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD]
  connect_bd_intf_net -intf_net zynq_ultra_ps_e_0_M_AXI_HPM1_FPD [get_bd_intf_pins ps8_0_axi_periph_1/S00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM1_FPD]

  # Create port connections
  connect_bd_net -net ADCIO_1 [get_bd_ports ADCIO] [get_bd_pins axi_gpio_0/gpio_io_i]
  connect_bd_net -net Net [get_bd_pins adc_cdc/s_axis_aresetn] [get_bd_pins adc_reset_512/peripheral_aresetn] [get_bd_pins usp_rf_data_converter_0/m0_axis_aresetn] [get_bd_pins usp_rf_data_converter_0/m1_axis_aresetn] [get_bd_pins usp_rf_data_converter_0/m2_axis_aresetn] [get_bd_pins usp_rf_data_converter_0/m3_axis_aresetn]
  connect_bd_net -net adc_clk_512_locked [get_bd_pins adc_clk_512/locked] [get_bd_pins adc_reset_512/dcm_locked]
  connect_bd_net -net adc_clk_512_out [get_bd_pins adc_cdc/s_axis_aclk] [get_bd_pins adc_clk_512/clk_out1] [get_bd_pins adc_reset_512/slowest_sync_clk] [get_bd_pins usp_rf_data_converter_0/m0_axis_aclk] [get_bd_pins usp_rf_data_converter_0/m1_axis_aclk] [get_bd_pins usp_rf_data_converter_0/m2_axis_aclk] [get_bd_pins usp_rf_data_converter_0/m3_axis_aclk]
  connect_bd_net -net adc_reset_256_peripheral_aresetn [get_bd_pins adc_clk_512/resetn] [get_bd_pins adc_dma_cdc_fifo/s_axis_aresetn] [get_bd_pins adc_reset_256/peripheral_aresetn] [get_bd_pins adc_reset_512/ext_reset_in] [get_bd_pins daq_axis_0/adc_resetn]
  connect_bd_net -net dac_reset_384_peripheral_aresetn [get_bd_pins dac_reset_384/peripheral_aresetn] [get_bd_pins daq_axis_0/dac_resetn] [get_bd_pins usp_rf_data_converter_0/s0_axis_aresetn] [get_bd_pins usp_rf_data_converter_0/s1_axis_aresetn]
  connect_bd_net -net daq_axis_0_lmh6401_cs_n [get_bd_ports cs_n] [get_bd_pins daq_axis_0/lmh6401_cs_n]
  connect_bd_net -net daq_axis_0_lmh6401_sck [get_bd_ports sck] [get_bd_pins daq_axis_0/lmh6401_sck]
  connect_bd_net -net daq_axis_0_lmh6401_sdi [get_bd_ports sdi] [get_bd_pins daq_axis_0/lmh6401_sdi]
  connect_bd_net -net ps_clk [get_bd_pins adc_dma_cdc_fifo/m_axis_aclk] [get_bd_pins adc_mux_config/aclk] [get_bd_pins awg_burst_length/aclk] [get_bd_pins awg_dma_error/s_axi_aclk] [get_bd_pins awg_frame_depth/aclk] [get_bd_pins awg_start_stop/aclk] [get_bd_pins awg_trigger_out_config/aclk] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] [get_bd_pins axi_dma_0/s_axi_lite_aclk] [get_bd_pins axi_gpio_0/s_axi_aclk] [get_bd_pins axi_smc/aclk] [get_bd_pins axi_smc_1/aclk] [get_bd_pins buffer_config/aclk] [get_bd_pins buffer_start_stop/aclk] [get_bd_pins buffer_timestamp_width/s_axi_aclk] [get_bd_pins dac_mux_config/aclk] [get_bd_pins dac_scale_config/aclk] [get_bd_pins daq_axis_0/ps_clk] [get_bd_pins dds_phase_inc/aclk] [get_bd_pins lmh6401_config/aclk] [get_bd_pins ps8_0_axi_periph/ACLK] [get_bd_pins ps8_0_axi_periph/M00_ACLK] [get_bd_pins ps8_0_axi_periph/S00_ACLK] [get_bd_pins ps8_0_axi_periph_1/ACLK] [get_bd_pins ps8_0_axi_periph_1/M00_ACLK] [get_bd_pins ps8_0_axi_periph_1/M01_ACLK] [get_bd_pins ps8_0_axi_periph_1/M02_ACLK] [get_bd_pins ps8_0_axi_periph_1/M03_ACLK] [get_bd_pins ps8_0_axi_periph_1/M04_ACLK] [get_bd_pins ps8_0_axi_periph_1/M05_ACLK] [get_bd_pins ps8_0_axi_periph_1/M06_ACLK] [get_bd_pins ps8_0_axi_periph_1/M07_ACLK] [get_bd_pins ps8_0_axi_periph_1/M08_ACLK] [get_bd_pins ps8_0_axi_periph_1/M09_ACLK] [get_bd_pins ps8_0_axi_periph_1/M10_ACLK] [get_bd_pins ps8_0_axi_periph_1/M11_ACLK] [get_bd_pins ps8_0_axi_periph_1/M12_ACLK] [get_bd_pins ps8_0_axi_periph_1/M13_ACLK] [get_bd_pins ps8_0_axi_periph_1/M14_ACLK] [get_bd_pins ps8_0_axi_periph_1/M15_ACLK] [get_bd_pins ps8_0_axi_periph_1/M16_ACLK] [get_bd_pins ps8_0_axi_periph_1/S00_ACLK] [get_bd_pins ps_reset_100/slowest_sync_clk] [get_bd_pins sample_discriminator_config/aclk] [get_bd_pins trigger_manager_config/aclk] [get_bd_pins usp_rf_data_converter_0/s_axi_aclk] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/maxihpm1_fpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] [get_bd_pins zynq_ultra_ps_e_0/saxihp2_fpd_aclk]
  connect_bd_net -net rst_ps8_0_99M_peripheral_aresetn [get_bd_pins adc_mux_config/aresetn] [get_bd_pins adc_reset_256/ext_reset_in] [get_bd_pins awg_burst_length/aresetn] [get_bd_pins awg_dma_error/s_axi_aresetn] [get_bd_pins awg_frame_depth/aresetn] [get_bd_pins awg_start_stop/aresetn] [get_bd_pins awg_trigger_out_config/aresetn] [get_bd_pins axi_dma_0/axi_resetn] [get_bd_pins axi_gpio_0/s_axi_aresetn] [get_bd_pins axi_smc/aresetn] [get_bd_pins axi_smc_1/aresetn] [get_bd_pins buffer_config/aresetn] [get_bd_pins buffer_start_stop/aresetn] [get_bd_pins buffer_timestamp_width/s_axi_aresetn] [get_bd_pins dac_mux_config/aresetn] [get_bd_pins dac_reset_384/ext_reset_in] [get_bd_pins dac_scale_config/aresetn] [get_bd_pins daq_axis_0/ps_resetn] [get_bd_pins dds_phase_inc/aresetn] [get_bd_pins lmh6401_config/aresetn] [get_bd_pins ps8_0_axi_periph/ARESETN] [get_bd_pins ps8_0_axi_periph/M00_ARESETN] [get_bd_pins ps8_0_axi_periph/S00_ARESETN] [get_bd_pins ps8_0_axi_periph_1/ARESETN] [get_bd_pins ps8_0_axi_periph_1/M00_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M01_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M02_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M03_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M04_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M05_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M06_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M07_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M08_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M09_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M10_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M11_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M12_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M13_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M14_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M15_ARESETN] [get_bd_pins ps8_0_axi_periph_1/M16_ARESETN] [get_bd_pins ps8_0_axi_periph_1/S00_ARESETN] [get_bd_pins ps_reset_100/peripheral_aresetn] [get_bd_pins sample_discriminator_config/aresetn] [get_bd_pins trigger_manager_config/aresetn] [get_bd_pins usp_rf_data_converter_0/s_axi_aresetn]
  connect_bd_net -net usp_rf_data_converter_0_clk_adc0 [get_bd_pins adc_cdc/m_axis_aclk] [get_bd_pins adc_clk_512/clk_in1] [get_bd_pins adc_dma_cdc_fifo/s_axis_aclk] [get_bd_pins adc_reset_256/slowest_sync_clk] [get_bd_pins daq_axis_0/adc_clk] [get_bd_pins usp_rf_data_converter_0/clk_adc0]
  connect_bd_net -net usp_rf_data_converter_0_clk_dac0 [get_bd_pins dac_reset_384/slowest_sync_clk] [get_bd_pins daq_axis_0/dac_clk] [get_bd_pins usp_rf_data_converter_0/clk_dac0] [get_bd_pins usp_rf_data_converter_0/s0_axis_aclk] [get_bd_pins usp_rf_data_converter_0/s1_axis_aclk]
  connect_bd_net -net zynq_ultra_ps_e_0_pl_resetn0 [get_bd_pins ps_reset_100/ext_reset_in] [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0]

  # Create address segments
  assign_bd_address -offset 0x000800000000 -range 0x000800000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_HIGH] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW] -force
  assign_bd_address -offset 0xC0000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_QSPI] -force
  assign_bd_address -offset 0x000800000000 -range 0x000800000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP4/HP2_DDR_HIGH] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP4/HP2_DDR_LOW] -force
  assign_bd_address -offset 0xC0000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP4/HP2_QSPI] -force
  assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0xB0120000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
  assign_bd_address -offset 0xB0040000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs sample_discriminator_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0050000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs buffer_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0060000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs adc_mux_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0070000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs buffer_start_stop/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0080000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs awg_frame_depth/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0090000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs awg_burst_length/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB00A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs awg_start_stop/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB00B0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs awg_trigger_out_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB00C0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs dac_mux_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB00D0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs trigger_manager_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB00E0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs dac_scale_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB00F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs dds_phase_inc/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0100000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs awg_dma_error/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0110000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs buffer_timestamp_width/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0130000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs lmh6401_config/fifo/S_AXI/Mem0] -force
  assign_bd_address -offset 0xB0000000 -range 0x00040000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs usp_rf_data_converter_0/s_axi/Reg] -force

  # Exclude Address Segments
  exclude_bd_addr_seg -offset 0xFF000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_LPS_OCM]
  exclude_bd_addr_seg -offset 0xFF000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP4/HP2_LPS_OCM]


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""



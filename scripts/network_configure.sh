#!/usr/bin/env bash


#################################
# 	helper functions	#
#################################

bold=$(tput bold)
normal=$(tput sgr0)

function print_bold() {
 echo "${bold}$1${normal}"
}


#################################
# 	helper functions	#
#################################

function join_by() { local IFS="$1"; shift; read joined_array <<< "$*"; }

function find_net_irq(){
  local net_id=$1
  irq=$(find /proc/irq/ -name "eno1" | cut -d '/' -f4)
  echo "${irq}"
}

#################################
# User input selction functions #
#################################

function get_user_single_cpu() {
  read -p "Select CPU [0-$((${NUM_CPUS}-1))] for network device: " selected_cpu

  if (( ${selected_cpu} > $((${NUM_CPUS}-1)) )); then
    echo "You selected CPU ${selected_cpu}, you only have ${NUM_CPUS}"
    return 1
  fi	
  return 0
}

function reset_user_default_or_not() {
  read -p "Configure network interface or to reset default? [conf/reset] " conf_or_reset
  case "$conf_or_reset" in
  conf)
    conf_net=1
    return 0
    ;;
  reset)
    conf_net=0
    return 0
    ;;
   *)
     print_bold "Please enter either 'conf' or 'reset'"
     return 1
     ;; 
   esac
}


#################################
# Network interface functions   #
#################################


function get_cpu_affinity_hex_mask(){
 local cpu_array
 IFS=',' read -r -a cpu_array <<< "$1"
 local NUM_CPUS="$(nproc --all)"
 local NUM_MASK=$(($NUM_CPUS/4))	

 # create empty binary mask for all cpus.
 local cpu_binary_mask=()
 for i in $(seq 0 $((${NUM_CPUS} - 1))); do
   cpu_binary_mask+=(0)
 done

 # set value to 1 for chose cpus
 for cpu in "${cpu_array[@]}"; do
  cpu_binary_mask[$cpu]=1
 done 
 
 # convert binary mask to hex
 HEX_CPU_AFFINITY_MASK=()
 for i in $(seq 0 $(( ${NUM_MASK}-1 )) ); do
  cpu_bin_mask=${cpu_binary_mask[@]:$((i*4)):$((i*4+4))}
  join_by '' ${cpu_bin_mask[@]}
  reversed_array=$(echo ${joined_array[@]} | rev)
  hex=$(printf '%x\n' "$((2#${reversed_array}))")
  HEX_CPU_AFFINITY_MASK=("${hex}${HEX_CPU_AFFINITY_MASK}")
 done
}

function get_default_affinity_hex_mask() {
  local NUM_CPUS="$(nproc --all)"
  local NUM_MASK=$(($NUM_CPUS/4))	
  local default_mask=""
  for i in $(seq 0 $((${NUM_MASK} - 1))); do
   default_mask="f${default_mask}"
  done
  echo $default_mask
}

function network_interface_selection(){
  #network_interfaces_display=()
  network_interfaces=()
  for iface in $(ifconfig | cut -d ' ' -f1| tr ':' '\n' | awk NF); do
   	ip=$(ifconfig | grep -A 1 $iface: | grep inet | awk '{print $2}')
    	# network_interfaces_display+=("$iface ($ip)")
	network_interfaces+=("$iface")
  done
  oldIFS=$IFS
  IFS=$'\n'
  IFS=$oldIFS
  PS3="Please enter your choice: "
  select net_interface in "${network_interfaces[@]}"; do
   	for item in "${network_interfaces[@]}"; do
      		if [[ $item == $net_interface ]]; then
        		break 2
      		fi
     	done
   done
}

#################################
# 	      Main		#
#################################

echo "============================"
echo "   Network configuration    "
echo "============================"

NUM_CPUS="$(nproc --all)"
network_interface_selection
echo "net_interface: ${net_interface}"
irq=$(find_net_irq "${net_interface}")

get_user_single_cpu
get_cpu_affinity_hex_mask "${selected_cpu}"

sudo chmod 777 /sys/class/net/"${net_interface}"/queues/rx-0/rps_cpus
sudo chmod 777 /sys/class/net/"${net_interface}"/queues/tx-0/xps_cpus
sudo sh -c "echo ${HEX_CPU_AFFINITY_MASK} > /sys/class/net/${net_interface}/queues/rx-0/rps_cpus"
sudo sh -c "echo ${HEX_CPU_AFFINITY_MASK} > /sys/class/net/${net_interface}/queues/tx-0/xps_cpus"
sudo sh -c "echo ${HEX_CPU_AFFINITY_MASK} > /proc/irq/${irq}/smp_affinity"







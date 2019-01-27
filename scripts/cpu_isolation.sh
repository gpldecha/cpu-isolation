#!/usr/bin/env bash

#################################
# 	helper functions	#
#################################

bold=$(tput bold)
normal=$(tput sgr0)

function print_bold() {
 echo "${bold}$1${normal}"
}

function print_green() {
 echo -e "\e[32m$1\e[0m"
}

function remove_white_space() {
 echo $(echo $1 | sed -e 's/^[ \t]*//')
}

function join_by() {
 local IFS="$1"; shift; read joined_array <<< "$*"; 
}

cpu_selected_contains() {
    local seeking=$1
    for value in "${CPU_SELECTED[@]}"
    do  
      if (( $value == $seeking )); then
        return 0
      fi
    done
    return 1
}

function get_core_cpu() {
 for i in $(seq 0 $(( ${NUM_CPUS}-1 )) ); do
  CORE_CPU[${CORE_ID[$i]}]+="${CPU_ID[${i}]},"
 done
 for i in $(seq 0 $(( ${NUM_CORES} -1 )) ); do
   var=${CORE_CPU[${i}]}
   CORE_CPU[${i}]="${var%?}"
 done
}

function print_core_cpu() {
  echo " core-cpu         : core -> cpus"
  for i in $(seq 0 $(( ${NUM_CORES}-1 )) ); do
  echo "                       ${i} -> ${CORE_CPU[$i]}"
  done
}

#################################
# CPU affinity hex computation  #
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



#################################
# User input selction functions #
#################################


function get_user_core_or_cpu() {
  read -p " Isolate individual CPUs or a single core? [core/cpu] " core_or_cpu
  case "$core_or_cpu" in
  core)
    use_core=1
    return 0
    ;;
  cpu)
    use_core=0
    return 0
    ;;
   *)
     print_bold " Please enter either 'core' or 'cpu'"
     return 1
     ;; 
   esac
}

function get_core() {
  read -p " Choose core within [0-$((${NUM_CORES}-1))] " core_selected
  if [ "$core_selected" -ge 0 -a "$core_selected" -le $(( ${NUM_CORES}-1 )) ]; then
    return 0
   else
    echo " Select number in range [0-$((${NUM_CORES}-1))] "	
    return 1
   fi
}

function get_cpu() {
  read -p " Enter comman sperated list of cpus within [0-$((${NUM_CPUS}-1))] " cpus_selected
  IFS=',' read -r -a CPU_SELECTED <<< "$cpus_selected"
  local num_selected_cpu=${#CPU_SELECTED[@]}
  if (( ${num_selected_cpu} > $((${NUM_CPUS}-1)) )); then
    echo " You selected ${num_selected_cpu} cpus, you only have ${NUM_CPUS}"
    return 1
  fi	
  for i in "${!CPU_SELECTED[@]}"
  do
     CPU_SELECTED[$i]=$(remove_white_space "${CPU_SELECTED[$i]}")
     if (( ${CPU_SELECTED[$i]} < 0 )); then
       print_bold " Cpus must be in range [0, $(( ${num_cpus}-1 ))], one of your chosen cpu was ${CPU_SELECTED[$i]}"
       return 1
     elif (( ${CPU_SELECTED[$i]} > $(($NUM_CPUS-1)) )); then
       print_bold " Cpus must be in range [0, $(( ${NUM_CPUS}-1 ))], one of your chosen cpu was ${CPU_SELECTED[$i]}"
       return 1     
     fi
  done
  return 0
}

#################################
#   High-level functions        #
#################################

# gets an array of cpus to isolate
function initialisation() {
  echo "============================"
  echo "      CPU Isolation         "
  echo "============================"
  echo " number of cores  : ${NUM_CORES}"
  echo " number of cpus   : ${NUM_CPUS}"
  print_core_cpu
  until get_user_core_or_cpu; do : ; done
  if (( $use_core == 1 )); then
    until get_core; do : ; done
    IFS=',' read -r -a CPU_SELECTED <<< "${CORE_CPU[${core_selected}]}"
  else
    until get_cpu; do : ; done
  fi
  echo " CPUs selected: ${CPU_SELECTED[@]}" 
}

function create_cgroup() {
    echo " Creating cgroup"
    sudo mount -t tmpfs none /sys/fs/cgroup
    sudo mkdir /sys/fs/cgroup/cpuset
    sudo mount -t cgroup -o cpuset none /sys/fs/cgroup/cpuset/
}

function create_cpuset() {
    echo " Creating real-time and non-real time cpuset"
    if [[ ! -d "/sys/fs/cgroup/cpuset/rt" ]]; then
        sudo mkdir /sys/fs/cgroup/cpuset/rt
        sudo mkdir /sys/fs/cgroup/cpuset/nrt
    fi
    sudo chown -R ${USER} /sys/fs/cgroup/cpuset/rt
    sudo chown -R ${USER} /sys/fs/cgroup/cpuset/nrt
    sudo chown -R ${USER} /sys/fs/cgroup/cpuset/
}

function assign_cpus() {
  print_green " Configure real-time and non real-time cpuset"
  NRT_CPUS=()
  for i in $(seq 0 $(( ${NUM_CPUS} -1 )) ); 
  do
    if ! cpu_selected_contains $i; then
	NRT_CPUS+=($i)
    fi
  done
  join_by , "${NRT_CPUS[@]}" 
  NRT_CPUS_STR="${joined_array[@]}"
  join_by , "${CPU_SELECTED[@]}" 
  RT_CPUS_STR="${joined_array[@]}"
  echo " Real time cpus     : ${RT_CPUS_STR}"
  echo " Non-real time cpus : ${NRT_CPUS_STR}"
  echo ${NRT_CPUS_STR} > /sys/fs/cgroup/cpuset/nrt/cpuset.cpus
  echo ${RT_CPUS_STR} > /sys/fs/cgroup/cpuset/rt/cpuset.cpus
  echo 1 > /sys/fs/cgroup/cpuset/rt/cpuset.cpu_exclusive
}

function configure_isolcpu() {
    print_green " Configuring isolcpu kernel boot parameters"
    rt_cpus="$1"
    line=$(grep GRUB_CMDLINE_LINUX_DEFAULT= /etc/default/grub)
    line_number=$(grep -n GRUB_CMDLINE_LINUX_DEFAULT= /etc/default/grub | grep -Eo '^[^:]+')
    line=${line%?}
    IFS=' ' read -ra SUBSTRINGS <<< "$line"
    new_line=""
    if [[ $line == *"isolcpus="*  ]]; then
        echo "  - already configured, updating to: isolcpus=$rt_cpus"
        NUM_SEGMENTS="${#SUBSTRINGS[@]}"
        for i in $(seq 0 $((${NUM_SEGMENTS} - 1)) ); do
            if [[ "${SUBSTRINGS[$i]}" == *"isolcpus="*  ]]; then
                SUBSTRINGS[$i]="isolcpus=$rt_cpus"
            fi
            new_line="${new_line} ${SUBSTRINGS[$i]}"
        done
        new_line="${new_line:1}\""
    else
        echo " - adding isolcpus=$rt_cpus to /etc/default/grub"
        new_line="${line} isolcpus=${rt_cpus}\""
        echo " - rebooting necessary for changes to take effect!"
    fi
    $(sudo sed -i "${line_number}s/.*/${new_line}/" /etc/default/grub)
    sudo update-grub
}

function configure_memory_allocation() {
    print_green " Configuring memory allocation"
    echo 0 > /sys/fs/cgroup/cpuset/nrt/cpuset.mems
    # echo 1 > /sys/fs/cgroup/cpuset/rt/cpuset.mems
    echo 1 > /sys/fs/cgroup/cpuset/rt/cpuset.mem_exclusive
}

function configure_load_balancing() {
    print_green " Configuring load balancing"
    echo 0 > /sys/fs/cgroup/cpuset/cpuset.sched_load_balance
    echo 0 > /sys/fs/cgroup/cpuset/rt/cpuset.sched_load_balance
    echo 1 > /sys/fs/cgroup/cpuset/nrt/cpuset.sched_load_balance
}

function move_irq() {
    print_green " Moving IRQs to non real-time CPUs $1"
    sudo chown -R ${USER} /proc/irq/default_smp_affinity
    echo $1 > /proc/irq/default_smp_affinity
    IRQs=(`ls -l --time-style="long-iso" /proc/irq | egrep '^d' | awk '{print $8}'`)
    for irq in "${IRQs[@]}"
    do
        {
            sudo chown -R ${USER} /proc/irq/$irq/smp_affinity
            echo $1 > /proc/irq/$irq/smp_affinity 2>&1
         } || {
            echo "   cannot move irq ${irq}"
         }
    done
}

function delay_vmstat_timer() {
 print_green " Delay vmstat timer"
 sudo sh -c "echo 1000 > /proc/sys/vm/stat_interval"
}

function disable_machine_check() {
 print_green " Disable machine check MCE"
 for cpu in "${CPU_SELECTED[@]}"
 do
   cpu_id=$((cpu+1))
    sudo sh -c "echo 0 > /sys/devices/system/machinecheck/machinecheck${cpu_id}/check_interval"
 done
}

function disable_watchdog() {
 print_green " Disable watchdog"
 sudo sh -c "echo 0 > /proc/sys/kernel/watchdog"
}

function disable_nmi_watchdog() {
 print_green " Disable NMI watchdog"
 sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog"
}

#################################
# 	      Main		#
#################################

# Variables

NUM_CPUS="$(nproc --all)"
NUM_CORES=$(($(cat /proc/cpuinfo | grep -m 1 "cpu cores" | awk '{print $4}')))
CPU_ID=($(cat '/proc/cpuinfo' | grep 'processor' | awk '{print $3}'))
CORE_ID=($(cat '/proc/cpuinfo' | grep 'core id' | awk '{print $4}'))
get_core_cpu

initialisation
create_cgroup
create_cpuset
assign_cpus
configure_isolcpu "${RT_CPUS_STR}"
configure_memory_allocation # would need a check to see if computer has NUMA architecture
configure_load_balancing
get_cpu_affinity_hex_mask "${NRT_CPUS_STR[@]}"
move_irq $HEX_CPU_AFFINITY_MASK
delay_vmstat_timer
disable_machine_check
disable_watchdog
disable_nmi_watchdog


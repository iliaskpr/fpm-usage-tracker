#!/usr/bin/env bash
#
# fpm-usage-tracker.sh
# Live PHP-FPM usage per user: process count and CPU %.
#
# Usage: ./fpm-usage-tracker.sh [interval_seconds]

interval=${1:-5}

if ! [[ $interval =~ ^[0-9]+$ ]] || [ "$interval" -eq 0 ]; then
    echo "Usage: $0 [interval_seconds]"
    echo "interval_seconds: whole number greater than 0 (default: 5)"
    exit 1
fi

clock_ticks=$(getconf CLK_TCK)   # CPU ticks per second
cpu_cores=$(nproc)

declare -A curr_ticks   # pid -> CPU ticks, current sample
declare -A curr_user    # pid -> user, current sample
declare -A prev_ticks   # pid -> CPU ticks, previous sample
declare -A user_procs   # user -> process count
declare -A user_ticks   # user -> CPU ticks used between samples

curr_time=0
prev_time=0

# Take a sample of all php-fpm processes
read_processes() {
    curr_ticks=()
    curr_user=()
    read -r curr_time _ < /proc/uptime

    while read -r pid user; do
        # Skip processes that exited after ps listed them
        if ! read -r -a fields 2>/dev/null < "/proc/$pid/stat"; then
            continue
        fi

        # Fields 14 and 15: user and system CPU time
        curr_ticks[$pid]=$(( fields[13] + fields[14] ))
        curr_user[$pid]=$user
    done < <(ps -eo pid=,user:32=,comm= | awk '$3 ~ /^php-fpm/ { print $1, $2 }')
}

# Exit cleanly on Ctrl+C
trap 'echo; exit 0' INT

echo "Collecting data, first result in ${interval}s..."
read_processes

while true; do
    # Keep the last sample for comparison
    prev_time=$curr_time
    prev_ticks=()
    for pid in "${!curr_ticks[@]}"; do
        prev_ticks[$pid]=${curr_ticks[$pid]}
    done

    sleep "$interval"
    read_processes

    # Real seconds between the two samples
    elapsed=$(awk -v a="$prev_time" -v b="$curr_time" 'BEGIN { print b - a }')

    # Add up processes and CPU ticks per user
    user_procs=()
    user_ticks=()

    for pid in "${!curr_ticks[@]}"; do
        user=${curr_user[$pid]}
        ticks=${curr_ticks[$pid]}

        # Known process: count only the new ticks.
        # New process or reused PID: count all ticks.
        old=${prev_ticks[$pid]:-0}
        if [ "$old" -le "$ticks" ]; then
            ticks=$(( ticks - old ))
        fi

        user_procs[$user]=$(( ${user_procs[$user]:-0} + 1 ))
        user_ticks[$user]=$(( ${user_ticks[$user]:-0} + ticks ))
    done

    clear
    echo "PHP-FPM usage per user - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Refresh: ${interval}s | CPU cores: $cpu_cores (100% = 1 core) | Ctrl+C to exit"
    echo

    if [ ${#user_procs[@]} -eq 0 ]; then
        echo "No php-fpm processes found."
        continue
    fi

    printf "%-24s %10s %8s\n" "USER" "PROCESSES" "CPU %"

    # One row per user, highest CPU first
    for user in "${!user_procs[@]}"; do
        cpu=$(awk -v t="${user_ticks[$user]}" -v hz="$clock_ticks" -v s="$elapsed" \
            'BEGIN { printf "%.1f", t / hz / s * 100 }')
        printf "%-24s %10s %8s\n" "$user" "${user_procs[$user]}" "$cpu"
    done | sort -k3,3 -nr
done

# fpm-usage-tracker

A Bash script that shows live PHP-FPM usage per system user. The script refreshes the screen at a fixed interval until you stop it with Ctrl+C.

For each user, the script shows these columns:

| Column      | Value                                                    |
|-------------|----------------------------------------------------------|
| `USER`      | The owner of the php-fpm processes                       |
| `PROCESSES` | The number of running php-fpm processes                  |
| `CPU %`     | The total CPU usage of these processes since the last refresh |

## Requirements

- Linux with `/proc`
- Bash 4 or later
- `ps` (procps), `awk`, `getconf`, `nproc` and `clear`

## Installation

1. Copy `fpm-usage-tracker.sh` to the server.
2. Make the script executable:

   ```bash
   chmod +x fpm-usage-tracker.sh
   ```

## Usage

```bash
./fpm-usage-tracker.sh [interval_seconds]
```

`interval_seconds` sets the refresh interval in seconds. The value must be a whole number greater than 0. The default is 5.

Examples:

```bash
# Refresh every 5 seconds
./fpm-usage-tracker.sh

# Refresh every 2 seconds
./fpm-usage-tracker.sh 2
```

To stop the script, push Ctrl+C.

The script shows the first result after one full interval. It needs two samples to calculate the CPU usage.

## Example output

```
PHP-FPM usage per user - 2026-10-11 15:20:05
Refresh: 5s | CPU cores: 8 (100% = 1 core) | Ctrl+C to exit

USER                      PROCESSES    CPU %
alice                             6     87.4
www-data                         12     23.0
bob                               3      0.4
root                              1      0.0
```

The script sorts the rows by CPU usage, from high to low.

## How it works

1. The script finds all processes with a name that starts with `php-fpm`. This includes versioned names, for example `php-fpm8.2`.
2. For each process, it reads the user and system CPU time from `/proc/<pid>/stat`.
3. After the interval, it reads the CPU times again and calculates the difference for each process.
4. It adds the differences per user. Then it divides each sum by the real time between the two samples.

The `CPU %` column uses the same scale as `top`: 100% is one full CPU core. On a server with 8 cores, the maximum value is 800%.

The `PROCESSES` column counts all php-fpm processes, idle and busy. The PHP-FPM master process usually runs as `root`. Thus, the list shows `root` with one process for each master.

## Notes

- Run the script as `root` to see the processes of all users. If `/proc` uses the `hidepid` mount option, a non-root user sees only their own processes.
- If a process stops between two samples, the script does not count its CPU usage for that interval.

#!/bin/bash
# sampler.sh OUT - every 2 s: time, GPU power (W), edge/junction temp (C), GPU busy %, VRAM used (MiB),
# MemAvailable (GiB), engine RSS (GiB, both engines' process names). Stops when the file STOP-sampler appears.
OUT=$1; D=$(dirname "$0")
dev=$(for c in /sys/class/drm/card*/device; do [ -f "$c/mem_info_vram_used" ] && echo "$c" && break; done)
hw=$(ls -d "$dev"/hwmon/hwmon* | head -1)
rm -f "$D/STOP-sampler"
echo "t power_w temp_edge temp_junc busy vram_mib memavail_gib engine_rss_gib" > "$OUT"
while [ ! -e "$D/STOP-sampler" ]; do
  p=$(( $(cat "$hw/power1_average" 2>/dev/null || cat "$hw/power1_input" 2>/dev/null || echo 0) / 1000000 ))
  te=$(( $(cat "$hw/temp1_input" 2>/dev/null || echo 0) / 1000 ))
  tj=$(( $(cat "$hw/temp2_input" 2>/dev/null || echo 0) / 1000 ))
  b=$(cat "$dev/gpu_busy_percent" 2>/dev/null)
  v=$(( $(cat "$dev/mem_info_vram_used") / 1048576 ))
  m=$(awk '/MemAvailable/ {printf "%.1f", $2/1048576}' /proc/meminfo)
  rss=$(ps -eo rss,comm | awk '/ds41_generate|strata-dsv41/ {s+=$1} END {printf "%.1f", s/1048576}')
  echo "$(date +%T) $p $te $tj $b $v $m $rss" >> "$OUT"
  sleep 2
done

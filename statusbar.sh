#!/usr/bin/env bash
# claude-status — self-contained Claude Code statusline (no external plugin).
# Line 1: model (ctx) effort | project (branch) Nf +A -D
# Line 2: bar PCT% CTX | 💰 $month/$cap pct% pace · 1d $today · 7d $week
#
# Cost is COMPUTED from token counts via ccusage (--mode calculate), because on
# Vertex/Bedrock/enterprise backends the transcripts carry no cost. It aggregates
# ALL sessions' logs, is cached, and refreshes in the background so rendering is
# instant. The figure uses public list prices → an ESTIMATE, not the invoice.

set -f
input=$(cat)
[ -z "$input" ] && { echo "Claude"; exit 0; }
command -v jq >/dev/null || { echo "Claude [needs jq]"; exit 0; }

CAP="${CLAUDE_MONTHLY_CAP:-500}"   # monthly soft cap in USD (override via env)
REFRESH=600                        # seconds before the cost cache refreshes
LOCK_TTL=180                       # min seconds between background refreshes
export PATH="$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# ── Colors ──
C=$'\033[36m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' N=$'\033[0m'
NOW=$(date +%s)

# ── Parse stdin + settings in one jq call ──
_SETTINGS=$(cat "$HOME/.claude/settings.json" 2>/dev/null)
echo "$_SETTINGS" | jq -e . >/dev/null 2>&1 || _SETTINGS='{}'
IFS=$'\t' read -r MODEL DIR PCT CTX EFF TIN < <(
  jq -r --argjson cfg "$_SETTINGS" \
    '[(.model.display_name//"?"),(.workspace.project_dir//"."),
    (.context_window.used_percentage//0|floor),(.context_window.context_window_size//0),
    (.effort.level//$cfg.effortLevel//"default"),
    (if (.context_window.total_input_tokens|type)=="number" then (.context_window.total_input_tokens|floor) else -1 end)]|@tsv' <<<"$input"
)
case "${EFF:-default}" in low) EF='low';; high) EF='high';; xhigh) EF='xhigh';; max) EF='max';; *) EF='medium';; esac

# ── Auto-compact window: measure the bar against the compaction threshold ──
ACW="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-0}"
if [[ "$ACW" =~ ^[0-9]+$ ]] && ((ACW > 0)) && [[ "$TIN" =~ ^[0-9]+$ ]]; then
  ((CTX > 0 && ACW > CTX)) && ACW=$CTX
  PCT=$((TIN * 100 / ACW)); ((PCT > 100)) && PCT=100
  CTX=$ACW
fi

# ── Context label ──
if ((CTX >= 1000000)); then CL="$((CTX / 1000000))M"
elif ((CTX > 0)); then CL="$((CTX / 1000))K"
else CL=""; fi

# ── Model short: append context label, cap total width ──
MODEL=${MODEL/ context)/)}
[[ "$CTX" -gt 0 && "$MODEL" != *"("* ]] && MODEL="${MODEL} (${CL})"
_ML="${MODEL} ${EF}"
((${#_ML} > 28)) && MODEL="${MODEL:0:$((28 - 2 - ${#EF}))}…"

# ── Context progress bar ──
F=$((PCT / 10)); ((F < 0)) && F=0; ((F > 10)) && F=10
if ((PCT >= 90)); then BC=$R; elif ((PCT >= 70)); then BC=$Y; else BC=$G; fi
BAR=""
for ((i = 0; i < F; i++)); do BAR+='█'; done
for ((i = F; i < 10; i++)); do BAR+='░'; done

# ── Git info (direct; --no-optional-locks keeps it read-only/fast) ──
BR="" FC=0 AD=0 DL=0
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BR=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null)
  while IFS=$'\t' read -r a d _; do
    [[ "$a" =~ ^[0-9]+$ ]] || continue
    FC=$((FC + 1)); AD=$((AD + a)); DL=$((DL + d))
  done < <(git -C "$DIR" --no-optional-locks diff HEAD --numstat 2>/dev/null)
fi

# ── Project name + line 1 right section ──
PN="${DIR##*/}"; IS_WT=0 _REPO=""
if [[ "${DIR/#$HOME/\~}" =~ /([^/]+)/\.claude/worktrees/([^/]+) ]]; then
  IS_WT=1; _REPO="${BASH_REMATCH[1]}"; _WT_NAME="${BASH_REMATCH[2]}"; PN="$_REPO"
fi
((${#PN} > 25)) && PN="${PN:0:25}…"
L1R="$PN"
if [ -n "$BR" ]; then
  ((${#BR} > 35)) && BR="${BR:0:35}…"
  L1R+=" (${BR})"
  ((FC > 0)) 2>/dev/null && L1R+=" ${FC}f ${G}+${AD}${N} ${R}-${DL}${N}"
elif [[ "$IS_WT" == "1" ]]; then
  L1R="${_REPO}/${_WT_NAME}"; ((${#L1R} > 25)) && L1R="${L1R:0:25}…"
fi

# ── Cost cache (month / week / today), refreshed in the background ──
CD=""
for BASE in "${XDG_RUNTIME_DIR:-}" "${HOME}/.cache"; do
  [ -n "$BASE" ] || continue
  CAND="${BASE%/}/claude-status"
  [ -e "$CAND" ] || mkdir -p -m 700 "$CAND" 2>/dev/null || continue
  [ -d "$CAND" ] && [ -w "$CAND" ] || continue
  CD="$CAND"; break
done
CACHE="" MO="?" WK="?" TD="?" COST_PCT=0 COST_OK=0
if [ -n "$CD" ]; then
  CACHE="$CD/cost-cache.json"; LOCK="$CD/cost-cache.lock"
  _stale() { local f="$1" ttl="$2" mt; [ -f "$f" ] || return 0; mt=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0); ((NOW - mt > ttl)); }
  _runner() { if command -v bunx >/dev/null 2>&1; then echo "bunx"; elif command -v npx >/dev/null 2>&1; then echo "npx --yes"; else return 1; fi; }
  _refresh() {
    local run month cutoff today json
    run=$(_runner) || return 1
    month=$(date +%Y-%m)
    today=$(date +%Y-%m-%d)
    cutoff=$(date -v-6d +%Y-%m-%d 2>/dev/null || date -d '6 days ago' +%Y-%m-%d 2>/dev/null)
    json=$($run ccusage@latest daily --mode calculate --json 2>/dev/null) || return 1
    [ -n "$json" ] || return 1
    printf '%s' "$json" | jq -c --arg m "$month" --arg cut "$cutoff" --arg td "$today" --argjson ts "$NOW" '
      { month: ([.daily[]? | select(.period|startswith($m)) | .totalCost] | add // 0),
        week:  ([.daily[]? | select(.period >= $cut)        | .totalCost] | add // 0),
        today: ([.daily[]? | select(.period == $td)         | .totalCost] | add // 0),
        ts: $ts }' >"$CACHE.tmp" 2>/dev/null && mv "$CACHE.tmp" "$CACHE"
  }
  if _stale "$CACHE" "$REFRESH" && _stale "$LOCK" "$LOCK_TTL" && mkdir "$LOCK" 2>/dev/null; then
    ( _refresh; rmdir "$LOCK" 2>/dev/null ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
  if [ -f "$CACHE" ]; then
    read -r _M _W _T < <(jq -r '"\(.month // 0) \(.week // 0) \(.today // 0)"' "$CACHE" 2>/dev/null)
    [[ "$_M" =~ ^[0-9.]+$ ]] && { MO=$(printf '%.0f' "$_M"); COST_OK=1; }
    [[ "$_W" =~ ^[0-9.]+$ ]] && WK=$(printf '%.0f' "$_W")
    [[ "$_T" =~ ^[0-9.]+$ ]] && TD=$(printf '%.0f' "$_T")
    ((COST_OK)) && COST_PCT=$(awk -v m="$_M" -v c="$CAP" 'BEGIN{ if(c<=0){print 0} else {printf "%d", (m*100/c)} }')
  fi
fi

# Cost color + pace vs how far through the month we are.
if ((COST_PCT >= 90)); then CCOL=$R; elif ((COST_PCT >= 70)); then CCOL=$Y; else CCOL=$G; fi
PACE=""
if ((COST_OK)); then
  DOM=$(date +%-d)
  LAST=$(date -v1d -v+1m -v-1d +%-d 2>/dev/null || echo 30); ((LAST > 0)) || LAST=30
  DELTA=$((COST_PCT - DOM * 100 / LAST))
  if ((DELTA > 0)); then PACE=" ${R}⇡${DELTA}%${N}"; elif ((DELTA < 0)); then PACE=" ${G}⇣${DELTA#-}%${N}"; fi
fi

# ── Assemble (pad shorter left section so the | aligns on both lines) ──
L1_PLAIN="${MODEL} ${EF}"
L2_PLAIN="${BAR} ${PCT}% ${CL}"
W1=${#L1_PLAIN} W2=${#L2_PLAIN} PAD1="" PAD2=""
if ((W1 > W2)); then printf -v PAD2 "%*s" $((W1 - W2)) ""
elif ((W2 > W1)); then printf -v PAD1 "%*s" $((W2 - W1)) ""; fi

# Cost section for line 2.
if ((COST_OK)); then
  COST_SEG="💰 ${CCOL}\$${MO}${N}${D}/\$${CAP}${N} ${CCOL}${COST_PCT}%${N}${PACE} ${D}· 1d \$${TD} · 7d \$${WK}${N}"
else
  COST_SEG="${D}💰 computing…${N}"
fi

L1="${C}${MODEL} ${EF}${N}${PAD1} ${D}|${N}  ${L1R}"
L2="${BC}${BAR}${N} ${PCT}% ${CL}${PAD2} ${D}|${N}  ${COST_SEG}"

printf '%b\n' "$L1"
printf '%b\n' "$L2"

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Claude Code Status Line  ·  api.z.ai edition
#  Shows: model · context bar · 5h quota · top tool
#
#  Install:
#    1. cp statusline.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
#    2. Add "statusLine" block to ~/.claude/settings.json (see settings-snippet.json)
#    3. Set Z_AI_API_KEY in your shell profile
#
#  Debug — see raw API response & parsed values:
#    echo '{}' | bash ~/.claude/statusline.sh --debug
#
#  Requires: curl, jq
# ─────────────────────────────────────────────────────────────────────────────

DEBUG=0
[[ "${1}" == "--debug" ]] && DEBUG=1

# ── Config ────────────────────────────────────────────────────────────────────
API_BASE="https://api.z.ai/api/monitor/usage"
# ── API Key — tries multiple locations, no manual export needed ───────────────
# Priority: env var → ~/.claude/.env → ~/.zairc → ~/.config/zai/key
API_KEY="YOUR_APIKEY_HERE"

if [[ -z "$API_KEY" ]]; then
  for f in \
    "$HOME/.claude/.env" \
    "$HOME/.zairc" \
    "$HOME/.config/zai/key"; do
    if [[ -f "$f" ]]; then
      API_KEY=$(grep -m1 'Z_AI_API_KEY' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'")
      [[ -n "$API_KEY" ]] && break
      # Also support bare key file (just the key, no variable name)
      bare=$(cat "$f" 2>/dev/null | tr -d '[:space:]')
      [[ -n "$bare" && "$bare" != *"="* ]] && API_KEY="$bare" && break
    fi
  done
fi
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
CACHE_TTL=60

# ── ANSI ──────────────────────────────────────────────────────────────────────
RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"
BG_BLACK="\033[40m"

# ── Session JSON from Claude Code ─────────────────────────────────────────────
SESSION=$(cat)
MODEL=$(echo "$SESSION"    | jq -r '.model.display_name // "unknown"' 2>/dev/null)
CTX_USED=$(echo "$SESSION" | jq -r '.context_window.used_percentage // 0' 2>/dev/null \
           | awk '{printf "%.0f", $1}')

# ── Context bar ───────────────────────────────────────────────────────────────
make_bar() {
  local pct=$1 width=12
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local color
  if   [[ $pct -ge 85 ]]; then color=$RED
  elif [[ $pct -ge 60 ]]; then color=$YELLOW
  else                          color=$GREEN
  fi
  echo -e "${color}$(printf '█%.0s' $(seq 1 $filled))${DIM}$(printf '░%.0s' $(seq 1 $empty))${RESET}"
}

# ── Cached fetch (background refresh, never blocks) ───────────────────────────
fetch_cached() {
  local key="$1" url="$2"
  local cache_file="$CACHE_DIR/${key}.json"
  local ts_file="$CACHE_DIR/${key}.ts"
  mkdir -p "$CACHE_DIR"

  local now; now=$(date +%s)
  local last_ts=0
  [[ -f "$ts_file" ]] && last_ts=$(cat "$ts_file")

  if (( now - last_ts >= CACHE_TTL )) || [[ ! -f "$cache_file" ]]; then
    (
      result=$(curl -sf --max-time 8 \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        "$url" 2>/dev/null)
      if [[ -n "$result" ]]; then
        echo "$result" > "$cache_file"
        echo "$now"    > "$ts_file"
      fi
    ) &
  fi

  [[ -f "$cache_file" ]] && cat "$cache_file" || echo "{}"
}

# ── Fetch ─────────────────────────────────────────────────────────────────────
QUOTA=$(fetch_cached "quota" "${API_BASE}/quota/limit")

# ── Debug: dump raw responses ─────────────────────────────────────────────────
if [[ $DEBUG -eq 1 ]]; then
  echo "=== QUOTA RAW ===" >&2
  echo "$QUOTA" | jq . >&2
  echo "=== TOOL_USAGE RAW ===" >&2
  echo "$TOOL_USAGE" | jq . >&2
fi

# ── Parse quota ───────────────────────────────────────────────────────────────
# TIME_LIMIT  = tool call usage (currentValue/usage), reset shown as date
# TOKENS_LIMIT unit=3 number=5 = 5-hour token quota (percentage only)

PLAN=$(echo "$QUOTA" | jq -r '.data.level // ""' 2>/dev/null)
TOOL_LIMIT_JSON=$(echo "$QUOTA" | jq '.data.limits[] | select(.type == "TIME_LIMIT")' 2>/dev/null)
FIVE_H_JSON=$(echo "$QUOTA"     | jq '.data.limits[] | select(.type == "TOKENS_LIMIT" and .number == 5)' 2>/dev/null)

# Tool usage
TOOL_USED=$(echo  "$TOOL_LIMIT_JSON" | jq -r '.currentValue // 0' 2>/dev/null)
TOOL_LIMIT=$(echo "$TOOL_LIMIT_JSON" | jq -r '.usage        // 0' 2>/dev/null)
TOOL_RESET_MS=$(echo "$TOOL_LIMIT_JSON" | jq -r '.nextResetTime // ""' 2>/dev/null)

# Convert ms epoch → date (e.g. "Feb 18")
TOOL_RESET=""
if [[ -n "$TOOL_RESET_MS" && "$TOOL_RESET_MS" != "null" ]]; then
  TOOL_RESET_S=$(( ${TOOL_RESET_MS%.*} / 1000 ))
  TOOL_RESET=$(date -d "@${TOOL_RESET_S}" "+%b %d %H:%M" 2>/dev/null \
            || date -r "${TOOL_RESET_S}"  "+%b %d %H:%M" 2>/dev/null \
            || echo "")
fi

# 5h token quota
FIVE_H_PCT=$(echo "$FIVE_H_JSON" | jq -r '.percentage // 0' 2>/dev/null)
FIVE_H_RESET_MS=$(echo "$FIVE_H_JSON" | jq -r '.nextResetTime // ""' 2>/dev/null)

FIVE_H_RESET=""
if [[ -n "$FIVE_H_RESET_MS" && "$FIVE_H_RESET_MS" != "null" ]]; then
  FIVE_H_RESET_S=$(( ${FIVE_H_RESET_MS%.*} / 1000 ))
  FIVE_H_RESET=$(date -d "@${FIVE_H_RESET_S}" "+%H:%M" 2>/dev/null \
              || date -r "${FIVE_H_RESET_S}"  "+%H:%M" 2>/dev/null \
              || echo "")
fi

if [[ $DEBUG -eq 1 ]]; then
  echo "=== QUOTA PARSED ===" >&2
  echo "  USED:     $QUOTA_USED"     >&2
  echo "  LIMIT:    $QUOTA_LIMIT"    >&2
  echo "  PCT:      $QUOTA_PCT"      >&2
  echo "  RESET_MS: $QUOTA_RESET_MS" >&2
  echo "  RESET:    $QUOTA_RESET"    >&2
fi

# ── Format segments ───────────────────────────────────────────────────────────

# 5h quota: color by percentage
fhpct=${FIVE_H_PCT%.*}
if   [[ $fhpct -ge 85 ]]; then fhcolor=$RED
elif [[ $fhpct -ge 60 ]]; then fhcolor=$YELLOW
else                            fhcolor=$GREEN
fi
five_h_bar=$(make_bar "$fhpct")
five_h_str="${five_h_bar} ${fhcolor}${fhpct}%${RESET}"

# Tool usage: color by percentage of limit
tool_pct=0
[[ $TOOL_LIMIT -gt 0 ]] && tool_pct=$(( TOOL_USED * 100 / TOOL_LIMIT ))
if   [[ $tool_pct -ge 85 ]]; then tcolor=$RED
elif [[ $tool_pct -ge 60 ]]; then tcolor=$YELLOW
else                               tcolor=$GREEN
fi
tool_str="${tcolor}${TOOL_USED}/${TOOL_LIMIT}${RESET}"

# ── Assemble ──────────────────────────────────────────────────────────────────
SEP="${DIM} │ ${RESET}"

short_model=$(echo "$MODEL" | sed 's/Claude //;s/ (.*)//')
plan_str=""
[[ -n "$PLAN" && "$PLAN" != "null" ]] && plan_str="  ◆ $(echo "$PLAN" | tr '[:lower:]' '[:upper:]')"
line="${CYAN}${BOLD}⬡ ${short_model}${plan_str}${RESET}"

bar=$(make_bar "$CTX_USED")
line+="${SEP}≋  ${bar}  ${CTX_USED}%"

line+="${SEP}⧗  5h  ${five_h_str}"
[[ -n "$FIVE_H_RESET" ]] && line+="${DIM}  ↻ ${FIVE_H_RESET}${RESET}"

line+="${SEP}⚙  tools  ${tool_str}"
[[ -n "$TOOL_RESET" ]] && line+="${DIM}  ↻ ${TOOL_RESET}${RESET}"

echo -e "${line}${RESET}"

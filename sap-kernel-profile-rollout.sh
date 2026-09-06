#!/bin/bash
###############################################################################
# SAP Fleet Kernel & Profile Rollout Assistant
#
# Interactively (or in dry-run mode) walks a list of SAP application servers,
# checks the current kernel version, and applies profile updates via sapcpe —
# with per-host confirmation, resume support, full logging, and a run summary.
#
# Designed for controlled, auditable kernel/profile rollout cycles across
# many hosts, without requiring an engineer to manually log into each one.
###############################################################################

[[ -z "$BASH_VERSION" ]] && { echo "This script must be run with bash."; exit 1; }

# ---------------- SCRIPT DIRECTORY ----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTFILE_NAME=$1
shift
DRYRUN=false
RESUME_HOST=""

# ---------------- ARG PARSING ----------------
while [[ $# -gt 0 ]]; do
   case "$1" in
       --dry-run)
           DRYRUN=true
           shift
           ;;
       --resume)
           RESUME_HOST="$2"
           shift 2
           ;;
       *)
           shift
           ;;
   esac
done

if [[ -z "$HOSTFILE_NAME" ]]; then
   echo "Usage: $0 <hostfile> [--dry-run] [--resume <hostname>]"
   exit 1
fi

HOSTFILE="$SCRIPT_DIR/$HOSTFILE_NAME"
if [[ ! -f "$HOSTFILE" ]]; then
   echo "Host file not found: $HOSTFILE"
   exit 1
fi

# ---------------- COLORS ----------------
if [[ -t 1 ]]; then
   RED='\033[0;31m'
   GREEN='\033[0;32m'
   YELLOW='\033[1;33m'
   CYAN='\033[0;36m'
   NC='\033[0m'
else
   RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""
fi

# ---------------- LOG FILE ----------------
LOGFILE="$SCRIPT_DIR/kernel_run_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"
echo -e "${CYAN}Logging to:${NC} $LOGFILE"
echo "----------------------------------------" | tee -a "$LOGFILE"

# ---------------- READ USERNAME ----------------
read -r USERNAME < "$HOSTFILE"
USERNAME=$(echo "$USERNAME" | xargs)
[[ -z "$USERNAME" ]] && { echo "Username missing in host file."; exit 1; }

# ---------------- SID & INSTANCE ----------------
read -p "Enter SID: " SID
read -p "Enter Instance: " INST
[[ -z "$SID" || -z "$INST" ]] && { echo "SID/Instance required."; exit 1; }

EXE_PATH="/usr/sap/${SID}/${INST}/exe"
PROFILE_PATH="/sapmnt/${SID}/profile"

# ---------------- COUNTERS ----------------
TOTAL=0
KERNEL_SUCCESS=0
KERNEL_FAIL=0
PROFILE_SUCCESS=0
PROFILE_FAIL=0
SKIP_KERNEL=0
SKIP_PROFILE=0

# ---------------- CLEAN EXIT FUNCTION ----------------
cleanup_and_exit() {
   EXIT_CODE=$1
   exec 3<&- 2>/dev/null
   echo ""
   echo -e "${CYAN}================== SUMMARY ==================${NC}" | tee -a "$LOGFILE"
   echo "Total Hosts Visited     : $TOTAL" | tee -a "$LOGFILE"
   echo "Kernel Success          : $KERNEL_SUCCESS" | tee -a "$LOGFILE"
   echo "Kernel Fail             : $KERNEL_FAIL" | tee -a "$LOGFILE"
   echo "Kernel Skipped          : $SKIP_KERNEL" | tee -a "$LOGFILE"
   echo "Profile Success         : $PROFILE_SUCCESS" | tee -a "$LOGFILE"
   echo "Profile Fail            : $PROFILE_FAIL" | tee -a "$LOGFILE"
   echo "Profile Skipped         : $SKIP_PROFILE" | tee -a "$LOGFILE"
   echo "Log File                : $LOGFILE" | tee -a "$LOGFILE"
   echo -e "${CYAN}=============================================${NC}" | tee -a "$LOGFILE"
   exit "$EXIT_CODE"
}

# ---------------- RESUME HANDLING ----------------
FOUND_RESUME=false
[[ -z "$RESUME_HOST" ]] && FOUND_RESUME=true

exec 3< <(tail -n +2 "$HOSTFILE")
while IFS= read -r LINE <&3
do
   LINE=$(echo "$LINE" | xargs)
   [[ -z "$LINE" ]] && continue

   HOST=$(echo "$LINE" | awk '{print $1}')
   PROFILE=$(echo "$LINE" | awk '{print $2}')
   [[ -z "$HOST" ]] && continue

   # Silent skip until resume host
   if [[ "$FOUND_RESUME" = false ]]; then
       if [[ "$HOST" == "$RESUME_HOST" ]]; then
           FOUND_RESUME=true
       else
           continue
       fi
   fi

   TOTAL=$((TOTAL + 1))
   echo ""
   echo -e "${CYAN}==================================================${NC}"
   echo -e "${CYAN}Host:${NC} $HOST"
   echo -e "${CYAN}Profile:${NC} $PROFILE"
   echo -e "${CYAN}==================================================${NC}"

   # -------- KERNEL CHECK --------
   while true; do
       read -p "Check kernel? (yes/skip/abort): " ACT < /dev/tty
       case "$ACT" in
           yes|y|Y)
               if $DRYRUN; then
                   echo -e "${YELLOW}[DRY-RUN] ./disp+work -v | head -n 20${NC}"
                   break
               fi
               timeout --kill-after=10 300 \
               pbrun -u "$USERNAME" -h "$HOST" SHELL <<EOF 2>&1 | tee -a "$LOGFILE"
cd "$EXE_PATH" || exit 2
./disp+work -v | head -n 30
EOF
               RC=${PIPESTATUS[0]}
               if [[ $RC -eq 0 ]]; then
                   ((KERNEL_SUCCESS++))
                   echo -e "${GREEN}Kernel OK${NC}"
               else
                   ((KERNEL_FAIL++))
                   echo -e "${RED}Kernel FAILED (RC=$RC)${NC}"
               fi
               break
               ;;
           skip|s|S)
               ((SKIP_KERNEL++))
               break
               ;;
           abort|a|A)
               echo "Aborting by user." | tee -a "$LOGFILE"
               cleanup_and_exit 1
               ;;
           *)
               echo "Invalid input."
               ;;
       esac
   done

   # -------- PROFILE UPDATE --------
   while true; do
       read -p "Update profile? (yes/next/abort): " ACT2 < /dev/tty
       case "$ACT2" in
           yes|y|Y)
               if [[ -z "$PROFILE" ]]; then
                   ((SKIP_PROFILE++))
                   break
               fi
               if $DRYRUN; then
                   echo -e "${YELLOW}[DRY-RUN] sapcpe pf=$PROFILE${NC}"
                   break
               fi
               timeout --kill-after=10 300 \
               pbrun -u "$USERNAME" -h "$HOST" SHELL <<EOF 2>&1 | tee -a "$LOGFILE"
cd "$PROFILE_PATH" || exit 2
sapcpe pf="$PROFILE"
EOF
               RC=${PIPESTATUS[0]}
               if [[ $RC -eq 0 ]]; then
                   ((PROFILE_SUCCESS++))
                   echo -e "${GREEN}Profile OK${NC}"
               else
                   ((PROFILE_FAIL++))
                   echo -e "${RED}Profile FAILED (RC=$RC)${NC}"
               fi
               break
               ;;
           next|n|N)
               ((SKIP_PROFILE++))
               break
               ;;
           abort|a|A)
               echo "Aborting by user." | tee -a "$LOGFILE"
               cleanup_and_exit 1
               ;;
           *)
               echo "Invalid input."
               ;;
       esac
   done
done
exec 3<&-

cleanup_and_exit 0

#!/bin/bash

LOG_PREFIX="[run-nwm-verf.sh]"

# This shell script lives in the nwm-verf repo.
# It is used by CerfServer runtime containers to invoke nwm-verf scripts.

VALID_COMMANDS=("verification")

SCRIPT_MODULE=nwm.verf

# Set the umask so files and directories are created with 777 permissions
umask 000

show_help() {
  echo "Usage: $(basename "$0") <command> <config_file> [stdout_file]"
  echo ""
  echo "COMMAND:"
  echo "  verification Run verification script."
  echo ""
  echo "CONFIG_FILE: Path to the config yaml file for a verification run."
  echo "STDOUT_FILE: Optional path where script console output will be saved."
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") verification test_data/verf_config.yaml"
  echo "  $(basename "$0") verification test_data/verf_config.yaml /path/to/output/nwm-verf.log"
  echo ""
  exit 1
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
fi

if [ -z "$1" ]; then
  echo "$LOG_PREFIX Error: No script command provided. Allowable commands are: ${VALID_COMMANDS[*]}."
  show_help
fi

SCRIPT_COMMAND=$1
shift 1

case "$SCRIPT_COMMAND" in
  "verification")
    REQUIRED_ARGS=1
    ;;
  *)
    echo "$LOG_PREFIX Error: Invalid script command: '$SCRIPT_COMMAND'. Allowable commands are: ${VALID_COMMANDS[*]}."
    show_help
    ;;
esac

if [ $# -lt "$REQUIRED_ARGS" ]; then
  echo "$LOG_PREFIX Error: Insufficient arguments. $SCRIPT_COMMAND requires $REQUIRED_ARGS arguments."
  show_help
fi

CONFIG_FILE=$1
shift 1

echo "$LOG_PREFIX CONFIG_FILE: $CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "$LOG_PREFIX Fatal: Configuration file not found at $CONFIG_FILE"
  exit 1
fi

STDOUT_FILE=""
if [ $# -ge 1 ]; then
  STDOUT_FILE=$1
  shift 1

  echo "$LOG_PREFIX Output file: $STDOUT_FILE"

  STDOUT_DIR=$(dirname "$STDOUT_FILE")
  mkdir --parents "$STDOUT_DIR"
fi

if [ $# -gt 0 ]; then
  echo "$LOG_PREFIX Error: Unexpected extra arguments: $*"
  show_help
fi

echo "$LOG_PREFIX Running $SCRIPT_MODULE with input file: $CONFIG_FILE"

if [ -z "$STDOUT_FILE" ]; then
  python -m "$SCRIPT_MODULE" "$CONFIG_FILE"
else
  python -m "$SCRIPT_MODULE" "$CONFIG_FILE" > "$STDOUT_FILE" 2>&1
fi

python_exit_code=$?

if [ $python_exit_code -ne 0 ]; then
  echo "$LOG_PREFIX $SCRIPT_MODULE exited with code $python_exit_code"
fi

if [ -n "$STDOUT_FILE" ]; then
  echo "$LOG_PREFIX Output from running $SCRIPT_MODULE"
  echo "-------------- start of $STDOUT_FILE -----------------------------"
  cat "$STDOUT_FILE"
  echo "---------------- end of $STDOUT_FILE -----------------------------"
fi

echo "$LOG_PREFIX Done running $SCRIPT_MODULE"

exit $python_exit_code

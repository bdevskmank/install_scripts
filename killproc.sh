#!/bin/bash

# Check if at least one argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 pattern1 [pattern2 pattern3 ...]"
    exit 1
fi

# Start building the grep pipeline
command="grep \"$1\""

# Shift to process remaining arguments
shift

# Append additional grep commands for each argument
for arg in "$@"; do
    command="$command | grep \"$arg\""
done

# Execute the command
eval  "kill -9 \$(ps -aux | $command | awk '{print \$2}')"
~                                                            

#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
cd "$repo_dir"
mkdir -p .build/research
clang -fobjc-arc -Wall -Wextra -Werror -I Sources/CSMCRead/include \
    tools/temperature_probe.m Sources/CSMCRead/SMCRead.c \
    -framework Foundation -framework IOKit -o .build/research/temperature-probe
clang -fobjc-arc -O2 -Wall -Wextra -Werror tools/temperature_workload.m \
    -framework Foundation -framework Metal -o .build/research/temperature-workload
echo "$repo_dir/.build/research/temperature-probe"

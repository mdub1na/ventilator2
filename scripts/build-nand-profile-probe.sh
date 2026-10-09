#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
cd "$repo_dir"
mkdir -p .build/research
clang -fobjc-arc -O2 -Wall -Wextra -Werror -I Sources/CHIDTemperature/include \
    tools/nand_profile_probe.m Sources/CHIDTemperature/HIDTemperatureRead.c \
    -framework Foundation -framework IOKit -o .build/research/nand-profile-probe

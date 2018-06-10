#!/bin/sh

# Convenience script enhancing functionality of repo and envsetup.sh
#
# 2018 Vasyl Gello <vasek.gello@gmail.com>
#

# functions

# start script

if [[ "$(basename -- "$0")" == "init.sh" ]]; then
    echo "Don't run $0, source it" >&2
    exit 1
fi

. build/envsetup.sh 1>/dev/null 2>/dev/null

alias mkbuildbranch='repo abandon _build; repo forall -c "BRANCHES=\$(git branch | grep -ioe \" _[0-9A-Za-z_-]*$\"); [ \$? -eq 0 ] && repo start _build . && for BRANCH in \$BRANCHES; do git merge \$BRANCH; done"'
alias killshell='rm -f ~/.bash_history && kill -9 $(pidof $0)'


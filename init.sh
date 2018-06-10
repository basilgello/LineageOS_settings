#!/bin/sh

# Convenience script enhancing functionality of repo and envsetup.sh
#
# 2018 Vasyl Gello <vasek.gello@gmail.com>
#

# functions

repopick_topic()
{
  # $1 is topic-name
  # $2 is Gerrit URL

  [ -z "$1" ] && echo "Usage: repopick_topic <topic-name> [gerrit-url]" && exit 1

  # check if topic-name is not a numeric ID
  echo "$1" | grep -ioe "[A-Za-z_-]" 1>/dev/null 2>/dev/null
  [ $? -ne 0 ] && echo "topic-name must not be the numeric change ID" && exit 1

  # perform repopick
  if [ -z "$2" ]; then
    repopick -s _"$1" -t "$1"
  else
    repopick -s _"$1" -t "$1" -g "$2"
  fi
}

# start script

if [[ "$(basename -- "$0")" == "init.sh" ]]; then
    echo "Don't run $0, source it" >&2
    exit 1
fi

. build/envsetup.sh 1>/dev/null 2>/dev/null

alias mkbuildbranch='repo abandon _build; repo forall -c "BRANCHES=\$(git branch | grep -ioe \" _[0-9A-Za-z_-]*$\"); [ \$? -eq 0 ] && repo start _build . && for BRANCH in \$BRANCHES; do git merge \$BRANCH; done"'
alias rmbuildbranch='repo abandon _build'
alias killshell='rm -f ~/.bash_history && kill -9 $(pidof $0)'

#!/bin/sh

# Convenience script enhancing functionality of repo and envsetup.sh
#
# 2018 Vasyl Gello <vasek.gello@gmail.com>
#

# functions

fcb()
{
  # $1 is file1
  # $2 is file2

  [ -z "$1" ] || [ -z "$2" ] && "Usage: fcb <file1> <file2>" && exit 1

  cmp -l "$1" "$2" |
    mawk 'function oct2dec(oct,    dec) {
              for (i = 1; i <= length(oct); i++) {
                  dec *= 8;
                  dec += substr(oct, i, 1)
              };
              return dec
          }
          {
              printf "%08X %02X %02X\n", $1-1, oct2dec($2), oct2dec($3)
          }'
}

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
    repopick -i -s _"$1" -t "$1"
  else
    repopick -i -s _"$1" -t "$1" -g "$2"
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

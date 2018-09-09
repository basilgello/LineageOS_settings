#!/bin/sh

# Convenience script enhancing functionality of repo and envsetup.sh
#
# 2018 Vasyl Gello <vasek.gello@gmail.com>
#

# functions

gerrit_cr()
{
  # $1 is review URL (review.lineageos.org)
  # $2 is quoted gerrit query ("status:open")
  # $3 is quoted code-review label ("-2", "-1", "0", "+1", "+2",  "n/a")
  # $4 is quoted verified label ("-1", "0", "+1", "n/a")

  CR_LABEL=""
  for LABEL in "-2" "-1" "0" "+1" "+2" "n/a"
  do
    [ "$LABEL" = "$3" ] && CR_LABEL="$LABEL" && break
  done

  [ -z "$CR_LABEL" ] && echo "ERROR: Code-Review label must be \"-2\", \"-1\", \"0\", \"+1\", \"+2\" or \"n/a\" to skip the label" && exit 1

  if [ "$CR_LABEL" = "n/a" ]
  then
    CR_LABEL=""
  else
    CR_LABEL="--code-review $CR_LABEL"
  fi

  V_LABEL=""
  for LABEL in "-1" "0" "+1" "n/a"
  do
    [ "$LABEL" = "$4" ] && V_LABEL="$LABEL" && break
  done

  [ -z "$V_LABEL" ] && echo "ERROR: Verified label must be \"-1\", \"0\", \"+1\" or \"n/a\" to skip the label" && exit 1

  if [ "$V_LABEL" = "n/a" ]
  then
    V_LABEL=""
  else
    V_LABEL="--verified $V_LABEL"
  fi

  IDS=""
  for ID in $(ssh -p 29418 "$1" 'gerrit query --current-patch-set "'$2'"' | grep "^    revision:" | sed 's,^    revision: ,,')
  do
    IDS="$ID $IDS"
  done

  ssh -p 29418 "$1" "gerrit review $CR_LABEL $V_LABEL $IDS"
}

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

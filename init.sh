#!/bin/sh

# Convenience script enhancing functionality of repo and envsetup.sh
#
# 2018 Vasyl Gello <vasek.gello@gmail.com>
#

# functions

gerrit_reconstruct_topic()
(
  # $1 is Gerrit server hostname
  # $2 is quoted Gerrit query string like "topic:xxx branch:yyy status:open"
  # $3 is output type ("--git" or "--repopick")

  # Some helper functions

  trap_cleanup()
  {
    rm -f "$CVE_TMPFILE"
    rm -f "$CVE0_TMPFILE"
    rm -f "$CVEREV_TMPFILE"
    rm -f "$CVEHEADS_TMPFILE"
  }

  GERRIT_HOSTNAME="$1"
  GERRIT_QUERY="$2"
  OUTPUT_FORMAT="$3"

  if [ -z "$GERRIT_HOSTNAME" ] || [ -z "$GERRIT_QUERY" ]
  then
    echo "Usage: reconstruct.sh <Gerrit-hostname> \"<Gerrit-query>\" [--output-format=git|repopick]"
    echo ""
    echo "Output formats:"
    echo "    repopick: print changes in NUMBER/PATCHSET format (newer first)"
    echo "              to use with repopick"
    echo "         git: print changes in Project ref format (newer first)"
    echo "              to use with git fetch"
    echo ""
    echo "If --output-format is not specified, default setting is \"repopick\""
    return
  fi

  if [ -z "$OUTPUT_FORMAT" ] || [ "$OUTPUT_FORMAT" = "--output-format=repopick" ]
  then
    OUTPUT_FORMAT=0
  elif [ "$OUTPUT_FORMAT" = "--output-format=git" ]
  then
    OUTPUT_FORMAT=1
  else
    echo "Output type must be --git or --repopick, exiting..."
    return
  fi

  CVE_TMPFILE=$(mktemp /tmp/cve-XXXXXXXXXXXXXXXX.txt)
  CVE0_TMPFILE=$(mktemp /tmp/cve0-XXXXXXXXXXXXXXXX.txt)
  CVEREV_TMPFILE=$(mktemp /tmp/cve-rev-XXXXXXXXXXXXXXXX.txt)
  CVEHEADS_TMPFILE=$(mktemp /tmp/cve-heads-XXXXXXXXXXXXXXXX.txt)

  trap trap_cleanup 1 2 3 6

  # Get the JSON list

  ssh -p 29418 "$GERRIT_HOSTNAME" "gerrit query --format JSON --current-patch-set $GERRIT_QUERY" > "$CVE_TMPFILE"

  # Prepare it for jq parse

  sed -i '/moreChanges/d' "$CVE_TMPFILE"
  echo '{"changes":[' >> "$CVE0_TMPFILE"
  sed 's|}$|},|' "$CVE_TMPFILE" >> "$CVE0_TMPFILE"
  echo "{\"project\":\"\",\"branch\":\"\",\"topic\":\"\",\"id\":\"\"}]}" >> "$CVE0_TMPFILE"
  mv "$CVE0_TMPFILE" "$CVE_TMPFILE"

  # Parse it with jq to get parent revisions

  i=0;
  while true
  do
    NUMBER=$(jq ".changes[$i].number" "$CVE_TMPFILE")
    [ -z "$NUMBER" ] || [ "$NUMBER" = "null" ] && break

    COMMIT=$(jq -r ".changes[$i].currentPatchSet.revision" "$CVE_TMPFILE")
    PARENT=$(jq -r ".changes[$i].currentPatchSet.parents[0]" "$CVE_TMPFILE")

    if [ $OUTPUT_FORMAT -eq 0 ]
    then
      PATCHSET=$(jq -r ".changes[$i].currentPatchSet.number" "$CVE_TMPFILE")

      echo "$NUMBER/$PATCHSET $COMMIT $PARENT" >> "$CVEREV_TMPFILE"
    else
      PROJECT=$(jq -r ".changes[$i].project" "$CVE_TMPFILE")
      REF=$(jq -r ".changes[$i].currentPatchSet.ref" "$CVE_TMPFILE")

      echo "$PROJECT+$REF $COMMIT $PARENT" >> "$CVEREV_TMPFILE"
    fi

    i=$((i + 1))
  done

  # Find the heads
  cat "$CVEREV_TMPFILE" | while read LINE
  do
    COMMIT=$(echo "$LINE" | awk '{print $2}')
    PARENT=$(echo "$LINE" | awk '{print $3}')
    grep " $COMMIT$" "$CVEREV_TMPFILE" 1>/dev/null 2>/dev/null
    [ $? -ne 0 ] && echo "$COMMIT" >> "$CVEHEADS_TMPFILE"
  done

  # Rewind the found heads

  for HEAD_REV in $(tac "$CVEHEADS_TMPFILE")
  do
    REV="$HEAD_REV"
    while true
    do
      if [ $OUTPUT_FORMAT -eq 0 ]
      then
        LINE=$(grep "^[0-9]*/[0-9]* $REV" "$CVEREV_TMPFILE")
      else
        LINE=$(grep "+refs/changes/[0-9]*/[0-9]*/[0-9]* $REV" "$CVEREV_TMPFILE")
      fi

      [ -z "$LINE" ] && break

      NUMBER=$(echo "$LINE" | awk '{print $1}')
      PARENT=$(echo "$LINE" | awk '{print $3}')

      if [ $OUTPUT_FORMAT -eq 0 ]
      then
        echo $NUMBER
      else
        NUMBER=$(echo "$NUMBER" | sed 's/+/ /')
        echo $NUMBER
      fi

      REV="$PARENT"
    done
  done

  # cleanup

  trap_cleanup
)

gerrit_cr()
{
  # $1 is review URL (review.lineageos.org)
  # $2 is quoted gerrit query ("status:open")
  # $3 is quoted code-review label ("-2", "-1", "0", "+1", "+2",  "n/a")
  # $4 is quoted verified label ("-1", "0", "+1", "n/a")

  [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] && [ -z "$4" ] && echo "Usage:" && echo "    gerrit_cr <review-server-host> <\"gerrit-query\"> <\"CR-label\"> <\"V-label\">" && return

  CR_LABEL=""
  for LABEL in "-2" "-1" "0" "+1" "+2" "n/a"
  do
    [ "$LABEL" = "$3" ] && CR_LABEL="$LABEL" && break
  done

  [ -z "$CR_LABEL" ] && echo "ERROR: Code-Review label must be \"-2\", \"-1\", \"0\", \"+1\", \"+2\" or \"n/a\" to skip the label" && return

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

  [ -z "$V_LABEL" ] && echo "ERROR: Verified label must be \"-1\", \"0\", \"+1\" or \"n/a\" to skip the label" && return

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

  [ -z "$1" ] || [ -z "$2" ] && "Usage: fcb <file1> <file2>" && return

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

  [ -z "$1" ] && echo "Usage: repopick_topic <topic-name> [gerrit-url]" && return

  # check if topic-name is not a numeric ID
  echo "$1" | grep -ioe "[A-Za-z_-]" 1>/dev/null 2>/dev/null
  [ $? -ne 0 ] && echo "topic-name must not be the numeric change ID" && return

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

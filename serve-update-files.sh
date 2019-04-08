#!/bin/bash

#
# Self-host the LineageOS update files
#
# Author:    Vasyl Gello <vasek.gello@gmail.com>
# Date:      08.04.2019
# Requires:  basename, busybox, dirname, grep, kill, mkdir
#            readlink, rm, sed, socat, unzip
#

SCRIPTDIR=$(readlink -f "$0")
SCRIPTDIR=$(dirname "$SCRIPTDIR")

# check hostname and domain of computer

SERVER_HOSTNAME=$(cat /etc/hostname)
SERVER_DNSDOMAIN=$(grep "^search " /etc/resolv.conf | sed 's|^search ||')
SERVER_PORT=8080

if [ -z "$SERVER_HOSTNAME" ]
then
    echo "Cannot determine server hostname! Exiting..."
    exit 1
fi

if [ ! -z "$SERVER_DNSDOMAIN" ]
then
    SERVER_URL="$SERVER_HOSTNAME.$SERVER_DNSDOMAIN"
else
    SERVER_URL="$SERVER_HOSTNAME"
fi

# Delete all updater reponses

if [ ! -d "$SCRIPTDIR/out/dist/updates" ]
then
    mkdir -p "$SCRIPTDIR/out/dist/updates"
fi

# Find all signed updates and create updater responses
#
# Expect the following name sequence:
# $BUILD_FLAVOR-$BUILD_VERSION-$BUILD_DATE-$BUILD_RELTYPE-$DEVICE_CANDIDATE
#

for SIGNED_FILE in $(find "$SCRIPTDIR/out/dist/" -type f -name "*-signed.zip")
do
    OTAFILENAME=$(basename "$SIGNED_FILE")
    OTAFILESIZE=$(stat -c "%s" "$SIGNED_FILE")

    # Extract the required props and generate resulting ZIP name

    BUILD_PROP=$(unzip -p "$SIGNED_FILE" system/build.prop)
    DEVICE_CANDIDATE=$(echo "$BUILD_PROP" | \
                    grep "ro.product.device" | \
                    grep -ioe "=.*$" | \
                    sed 's#=##')
    BUILD_VERSION=$(echo "$BUILD_PROP" | \
                    grep "ro.cm.build.version=" | \
                    grep -ioe "=.*$" | \
                    sed 's#=##')
    BUILD_RELTYPE=$(echo "$BUILD_PROP" | \
                    grep "ro.cm.releasetype" | \
                    grep -ioe "=.*$" | \
                    sed 's#=##')
    BUILD_DATE_TS=$(echo "$BUILD_PROP" | \
                    grep "ro.build.date.utc" | \
                    grep -ioe "=[0-9]*$" | \
                    sed 's#=##')

    BUILD_RELEASE_CHANNEL=$(echo "$BUILD_RELTYPE" | tr '[:upper:]' '[:lower:]')

    # Generate updater file

    cat << UPDATERFILE > "$SCRIPTDIR/out/dist/updates/$DEVICE_CANDIDATE"_"$BUILD_RELEASE_CHANNEL"
{
  "response": [
    {
      "datetime": $BUILD_DATE_TS,
      "filename": "$OTAFILENAME",
      "id": "$BUILD_DATE_TS-$OTAFILENAME",
      "romtype": "$BUILD_RELTYPE",
      "size": $OTAFILESIZE,
      "url": "https://$SERVER_URL:$SERVER_PORT/$OTAFILENAME",
      "version": "$BUILD_VERSION"
    }
  ]
}
UPDATERFILE

done

# Start the HTTP server

which busybox 1>/dev/null 2>/dev/null
if [ $? -ne 0 ]
then
    echo "ERROR: Can not start busybox httpd - busybox missing!"
    exit 1
else
    echo "Starting HTTPS server on port $SERVER_PORT. Press Enter to stop..."
    OLDPWD="$PWD"
    cd "$SCRIPTDIR/out/dist"
    busybox httpd -v -f -p 127.0.0.1:62000 &
    BUSYBOX_PID=$!
    socat OPENSSL-LISTEN:$SERVER_PORT,reuseaddr,fork,pf=ip6,certificate="$SCRIPTDIR/certs/$SERVER_URL.pem",verify=0 TCP:127.0.0.1:62000 &
    read -s password
    kill $BUSYBOX_PID $(ps aux | grep OPENSSL-LISTEN | grep -v grep | awk '{print $2}')
    echo "HTTPS Server on port $SERVER_PORT terminated, have fun!"
    cd "$OLDPWD"
fi

# Delete the updater response files

rm -f $SCRIPTDIR/out/dist/updates/*


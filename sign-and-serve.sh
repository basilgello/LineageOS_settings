#!/bin/bash

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

# check if certificates are present

if [ ! -d "$SCRIPTDIR/certs" ] || [ ! -e "$SCRIPTDIR/certs/releasekey.x509.pem" ]
then
    echo "No certificates generated yet!"
    echo "Please run generate-signing-keys.sh"
    echo "Exiting..."
    exit 1
fi

if [ -d "$SCRIPTDIR/out/dist/updates" ]
then
    rm -f $SCRIPTDIR/out/dist/updates/*
else
    mkdir -p "$SCRIPTDIR/out/dist/updates"
fi

# Ask for signing keys unlock password

echo -n "Enter password: "
read -s password
echo

# Start signing the target files and forming the update files
# to be served by LineageOS updater app

for DEVICE_DIR in $(find "$SCRIPTDIR/device/" -mindepth 2 -maxdepth 2 -type d)
do
    DEVICE_CANDIDATE=$(basename "$DEVICE_DIR")

    FW_COUNT=$(find "$SCRIPTDIR/out/dist/" -name "*$DEVICE_CANDIDATE-target_files-*.zip" | wc -l)
    [ $FW_COUNT -eq 0 ] && continue

    echo "Signing $DEVICE_CANDIDATE..."

    for TARGET_FILES_ZIP in $SCRIPTDIR/out/dist/*$DEVICE_CANDIDATE-target_files-*.zip
    do
        # sign target APKs

        export ANDROID_SECURE_STORAGE_CMD="echo '$password'"
        "$SCRIPTDIR/build/tools/releasetools/sign_target_files_apks" \
        -o -d "$SCRIPTDIR/certs" \
        "$TARGET_FILES_ZIP" \
        "$TARGET_FILES_ZIP.signed"

        if [ $? -ne 0 ]
        then
            rm -f "$TARGET_FILES_ZIP.signed"
            exit 1
        fi

        # Extract the required props and generate resulting ZIP name

        BUILD_PROP=$(unzip -p "$TARGET_FILES_ZIP" SYSTEM/build.prop)
        BUILD_FLAVOR=$(echo "$BUILD_PROP" | \
                       grep "ro.build.flavor" | \
                       grep -ioe "=.*_$DEVICE_CANDIDATE" | \
                       sed 's#=##' | \
                       sed "s|_$DEVICE_CANDIDATE.*$||")
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
        BUILD_DATE=$(date +%Y%m%d -d @$BUILD_DATE_TS)

        OTAFILENAME="$BUILD_FLAVOR-$BUILD_VERSION-$BUILD_DATE-$BUILD_RELTYPE-$DEVICE_CANDIDATE-signed.zip"

        # Sign the final OTA

        "$SCRIPTDIR/build/tools/releasetools/ota_from_target_files" \
        -k "$SCRIPTDIR/certs/releasekey" \
        --block --backup=true \
        "$TARGET_FILES_ZIP.signed" \
        "$SCRIPTDIR/out/dist/$OTAFILENAME"

        if [ $? -ne 0 ]
        then
            rm -f "$TARGET_FILES_ZIP.signed"
            rm -f "$SCRIPTDIR/out/dist/$OTAFILENAME"
            exit 1
        fi

        OTAFILESIZE=$(stat -c "%s" "$SCRIPTDIR/out/dist/$OTAFILENAME")

        # Generate updater file

        BUILD_RELEASE_CHANNEL=$(echo "$BUILD_RELTYPE" | tr '[:upper:]' '[:lower:]')
        cat << UPDATERFILE > "$SCRIPTDIR/out/dist/updates/$DEVICE_CANDIDATE"_"$BUILD_RELEASE_CHANNEL"
{
  "response": [
    {
      "datetime": $BUILD_DATE_TS,
      "filename": "$OTAFILENAME",
      "id": "5eb63bbbe01eeed093cb22bb8f5acdc3",
      "romtype": "$BUILD_RELTYPE",
      "size": $OTAFILESIZE,
      "url": "https://$SERVER_URL:$SERVER_PORT/$OTAFILENAME",
      "version": "$BUILD_VERSION"
    }
  ]
}
UPDATERFILE

        # Cleanup intermediate files

        rm -f "$TARGET_FILES_ZIP.signed"
        rm -f "$TARGET_FILES_ZIP"
    done
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

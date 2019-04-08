#!/bin/bash

#
# Sign the LineageOS update files
#
# Author: Vasyl Gello <vasek.gello@gmail.com>
# Date:   08.04.2019
#

SCRIPTDIR=$(readlink -f "$0")
SCRIPTDIR=$(dirname "$SCRIPTDIR")

# Check if build config file is present

if [  -e "$SCRIPTDIR/build.config" ]
then
  . "$SCRIPTDIR/build.config"
else
  echo "No build config found!"
    echo "Exiting..."
    exit 1
fi

# Check if certificates are present

if [ ! -d "$SCRIPTDIR/certs" ] || [ ! -e "$SCRIPTDIR/certs/releasekey.x509.pem" ]
then
    echo "No certificates generated yet!"
    echo "Please run generate-signing-keys.sh"
    echo "Exiting..."
    exit 1
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

        # Rewrite the build.prop with custom Lineage updater URI and
        # inject the pinned CA certificate if required

        if [ ! -z "$CUSTOM_UPDATER_URL" ]
        then
            unzip "$TARGET_FILES_ZIP" SYSTEM/build.prop \
                META/filesystem_config.txt \
                -d "$SCRIPTDIR/out/dist/"

            if [ $? -ne 0 ]
            then
                exit 1
            fi

            pushd "$SCRIPTDIR/out/dist"

            sed -i '/lineage.updater.uri/d' "SYSTEM/build.prop"

            # Place proper updater URL property depending on build version

            BUILD_VERSION_NUMBER=$(( $(echo "$BUILD_VERSION" | sed 's/\..*$//') ))
            if [ $BUILD_VERSION_NUMBER -lt 15 ]
            then
                echo "cm.updater.uri=$CUSTOM_UPDATER_URL" >> "SYSTEM/build.prop"
            else
                echo "lineage.updater.uri=$CUSTOM_UPDATER_URL" >> "SYSTEM/build.prop"
            fi

            if [ -e "$SCRIPTDIR/certs/rootCA.pem" ]
            then
                mkdir "SYSTEM/etc"
                cp "$SCRIPTDIR/certs/rootCA.pem" "SYSTEM/etc/updater-ca.pem"
                echo "system/etc/updater-ca.pem 0 0 644 \
                      selabel=u:object_r:system_file:s0 capabilities=0x0" >> \
                      META/filesystem_config.txt
            fi

            zip -r "$TARGET_FILES_ZIP" SYSTEM META

            if [ $? -ne 0 ]
            then
                popd
                rm -rf SYSTEM
                rm -rf META
                exit 1
            fi

            rm -rf SYSTEM
            rm -rf META
            popd
        fi

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

        # Cleanup intermediate files

        rm -f "$TARGET_FILES_ZIP.signed"
        rm -f "$TARGET_FILES_ZIP"
    done
done

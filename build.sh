#!/bin/bash

export LC_ALL=C

SCRIPTDIR="$(readlink -f "$0")"
SCRIPTDIR="$(dirname "$SCRIPTDIR")"

cd "$SCRIPTDIR"
. build/envsetup.sh

# Clean everything
if [ "$1" = "clean" ]; then
  make clean
  exit 0
fi

# Boot image build:
if [ "$1" = "bootimage" ]; then
  # remove old kernel components
  rm -f $SCRIPTDIR/out/target/product/chagalllte/boot.img
  rm -f $SCRIPTDIR/out/target/product/chagalllte/ramdisk.img
  rm -f $SCRIPTDIR/out/target/product/chagalllte/recovery.img
  rm -f $SCRIPTDIR/out/target/product/chagalllte/recovery.id
  rm -f $SCRIPTDIR/out/target/product/chagalllte/kernel
  rm -f $SCRIPTDIR/out/target/product/chagalllte/recovery-ramdisk.cpio
  rm -rf $SCRIPTDIR/out/target/product/chagalllte/obj/KERNEL_OBJ

  # load chagalllte device tree
  breakfast chagalllte

  # build boot image
  make bootimage
  exit $?
fi

# Single module build:
if [ ! -z "$1" ]; then
  # load chagalllte device tree
  breakfast chagalllte

  # build module
  mmma "$1"
  exit $?
fi

# Normal build:

# configure jack
export ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4G"

# delete old falshable zips and object files
rm -f $SCRIPTDIR/out/target/product/chagalllte/*.img
rm -f $SCRIPTDIR/out/target/product/chagalllte/*.zip*
rm -f $SCRIPTDIR/out/target/product/chagalllte/kernel
rm -f $SCRIPTDIR/out/target/product/chagalllte/recovery-ramdisk.cpio
rm -rf $SCRIPTDIR/out/target/product/chagalllte/obj/PACKAGING
rm -rf $SCRIPTDIR/out/target/product/chagalllte/obj/KERNEL_OBJ

# load chagallte device tree
breakfast chagalllte

# check for newest tzdata
python -B external/icu/tools/update-tzdata.py

# build the flashable zips
brunch chagalllte
RET=$?

# kill all jack instances
JACK_PIDS=$(ps aux | grep -v grep | grep "bin/jack" 2>/dev/null)
if [ ! -z "$JACK_PIDS" ]; then
  kill $JACK_PIDS
fi

JACK_PIDS=$(ps aux | grep -v grep | grep "java" | grep "jack" | awk '{print $2}' 2>/dev/null)
if [ ! -z "$JACK_PIDS" ]; then
  kill $JACK_PIDS
fi

# Report success
exit $RET

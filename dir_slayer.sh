#!/usr/bin/bash
#
# Script to create a faulty directory.
# Arguments:
#   $1: directory to mirror into the faulty device.
# 	$2: whether to copy or to symlink
#   $3: whether to fail the directory

datetime=`date "+%Y-%m-%d-%H%M%S"`
src_dir=`stat -f "%N" $1`

if [[ $2 == "copy" ]]; then
  copy=true
elif [[ $2 == "link" ]]; then
  copy=false
else
  echo copy argument must be either 'copy' or 'link'
  exit 1
fi

if [[ $3 == "fail" ]]; then
  fail_dir=true
elif [[ $3 == "nofail" ]]; then
  fail_dir=false
else
  echo fail_dir argument must be either 'fail' or 'nofail'
  exit 1
fi

# Create a backup of the existing directory if one already exists.
backup=$src_dir.bak.$datetime
if [[ -e $src_dir ]]; then
  mv $src_dir $backup
fi

# Canonicalize the input directory.
faultfile=$src_dir.faultfile.$datetime
echo Using file as the base of the loop device: $faultyfile

# Create a file large enough to hold the fs. The minimum size is 512B.
# Adjust `bs` based on the output of `state -f "%k" .` (tells you the block size of `.`)
# Adjust `count` based on the desired size of the filesystem.
block_size=`stat -f "%k" $src_dir`
# TODO: assign a reasonable count
dd if=/dev/zero of=$faultfile bs=$block_size count=1024

# Create a loop device out of the file.
losetup -f $faultfile

loop_device=''

# Allow parsing of '\n'-terminated lines
IFS=$'\n'

# Get the name of the loop device we just created.
for dev in `losetup -a | grep $faultfile`; do
  echo "$dev";
  loop_candidate=`echo $dev | sed -r 's/(\/dev\/loop[0-9]+).*/\1/'`;
  if [ "$dev" != "$loop_device" ]; then
    loop_device=$loop_candidate
    break;
  fi
done
if [ "$loop_device" == "" ]; then
  echo Could not find a loop device for $faultfile
  rm $faultfile
  exit 0
fi
echo Using first found loop device for $faulty_device: $loop_device

# Get the name of the first available md device.
highest_md=""
for line in `cat /proc/mdstat`; do
  echo $line
  md_candidate=`echo $line | sed -r 's/md([0-9]+)\s*:.*/\1/'`;
  if [ "$line" != "$md_candidate" ]; then
    highest_md=$md_candidate
    break;
  fi
done;
md_int="0"
if [ "$highest_md" == "" ]; then
  echo No md instances found
else
  echo Last md instance found: md$highest_md
  # Convert the md to an int and add 1.
  md_int=$(expr $highest_md + 1)
fi
md=/dev/md$md_int

unset IFS

echo Creating device $md
mdadm --create $md --level=faulty --raid-devices=1 $loop_device
mkfs.ext4 $md

mkdir $src_dir
if [[ copy=true ]]; then
  cp -R $backup/* $src_dir
else
  lndir $backup $src_dir
fi

set -x

mount $md $src_dir

if [[ faildir=true ]]; then
  mdadm --grow $md -l faulty -p write-all
else
  echo To fail the directory, run: mdadm --grow $md -l faulty -p write-all
fi

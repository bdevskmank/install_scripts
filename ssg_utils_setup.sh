#!/bin/bash
chmod a+x gitclone.sh
./gitclone.sh   $UTIL_URL $USERNAME $UTIL_FOLDER $PAT
cd $UTIL_FOLDER
tar xf src.tar.gz
mkdir /mnt/tmp_ramfs
sudo mount -t ramfs -o size=32g ramfs /mnt/tmp_ramfs
mv $UTIL_FOLDER/subsinfo /mnt/tmp_ramfs/data/
mv $UTIL_FOLDER/siteveip /mnt/tmp_ramfs/data/

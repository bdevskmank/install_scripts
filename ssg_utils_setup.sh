#!/bin/bash




chmod a+x gitclone.sh


./gitclone.sh   $UTIL_URL $USERNAME $UTIL_FOLDER $PAT
cd $UTIL_FOLDER
tar xf src.tar.gz
mkdir -p /mnt/tmp_fs/data
mv $UTIL_FOLDER/subsinfo /mnt/tmp_fs/data/
mv $UTIL_FOLDER/siteveip /mnt/tmp_fs/data/

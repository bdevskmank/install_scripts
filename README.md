Following values shall be exported: 
export OS_USER=
export USER_HOME_FOLDER=

export USERNAME=
export PAT=
export NDPI_URL=
export NDPI_FOLDER=
export UTIL_URL=
export UTIL_FOLDER=


./dpdk-install.sh
./ndpi_install.sh
./install_redis_pgsql.sh
./dpdk_bind.sh  ## for time being applies only to irtual env.
./ssg_utils_setup.sh

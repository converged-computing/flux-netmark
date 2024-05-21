#!/bin/bash

set -eu pipefail

################################################################
## Install dependencies (I added stuff for bdf too)
#
# This also includes EFA
#

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && \
    sudo apt-get upgrade -y && \
    sudo apt-get install -y apt-transport-https ca-certificates curl clang llvm jq apt-utils wget \
         libelf-dev libpcap-dev libbfd-dev binutils-dev build-essential make \
         linux-tools-common linux-tools-$(uname -r)  \
         bpfcc-tools python3-pip git net-tools

# cmake is needed for flux-sched
export CMAKE=3.23.1
curl -s -L https://github.com/Kitware/CMake/releases/download/v$CMAKE/cmake-$CMAKE-linux-x86_64.sh > cmake.sh && \
    sudo sh cmake.sh --prefix=/usr/local --skip-license && \
    sudo apt-get install -y man flex ssh sudo vim luarocks munge lcov ccache lua5.2 \
         valgrind build-essential pkg-config autotools-dev libtool \
         libffi-dev autoconf automake make clang clang-tidy \
         gcc g++ libpam-dev apt-utils \
         libsodium-dev libzmq3-dev libczmq-dev libjansson-dev libmunge-dev \
         libncursesw5-dev liblua5.2-dev liblz4-dev libsqlite3-dev uuid-dev \
         libhwloc-dev libs3-dev libevent-dev libarchive-dev \
         libboost-graph-dev libboost-system-dev libboost-filesystem-dev \
         libboost-regex-dev libyaml-cpp-dev libedit-dev uidmap dbus-user-session

# Important - openmpi for flux
# This is commented out so we use the aws openmpi
# sudo apt-get install -y openmpi-bin openmpi-doc libopenmpi-dev 

# Let's use mamba python and do away with system annoyances
export PATH=/opt/conda/bin:$PATH
curl -L https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh > mambaforge.sh && \
#curl -L https://github.com/conda-forge/miniforge/releases/download/23.11.0-0/Mambaforge-23.11.0-0-Linux-aarch64.sh > mambaforge.sh && \
    sudo bash mambaforge.sh -b -p /opt/conda && \
    sudo chown $USER -R /opt/conda && \
    pip install --upgrade --ignore-installed markupsafe coverage cffi ply six pyyaml jsonschema && \
    pip install --upgrade --ignore-installed sphinx sphinx-rtd-theme sphinxcontrib-spelling

# Prepare lua rocks (does it really rock?)
sudo apt-get install -y faketime libfaketime pylint cppcheck aspell aspell-en && \
    sudo locale-gen en_US.UTF-8 && \
    sudo luarocks install luaposix

# This is needed if you intend to use EFA (HPC instance type)
# Install EFA alone without AWS OPEN_MPI
# At the time of running this, latest was 1.32.0
export EFA_VERSION=latest
mkdir /tmp/efa 
cd /tmp/efa
curl -O https://s3-us-west-2.amazonaws.com/aws-efa-installer/aws-efa-installer-${EFA_VERSION}.tar.gz
tar -xf aws-efa-installer-${EFA_VERSION}.tar.gz
cd aws-efa-installer
sudo ./efa_installer.sh -y

# update-initramfs: Generating /boot/initrd.img-6.5.0-1017-aws
# libfabric1-aws is verified to install /opt/amazon/efa/lib/libfabric.so
# openmpi40-aws is verified to install /opt/amazon/openmpi/lib/libmpi.so
# openmpi50-aws is verified to install /opt/amazon/openmpi5/lib/libmpi.so
# efa-profile is verified to install /etc/ld.so.conf.d/000_efa.conf
# efa-profile is verified to install /etc/profile.d/zippy_efa.sh
# Reloading EFA kernel module
# EFA device not detected, skipping test.
# ===================================================
# EFA installation complete.
# - Please logout/login to complete the installation.
# - Libfabric was installed in /opt/amazon/efa
# - Open MPI 4 was installed in /opt/amazon/openmpi
# - Open MPI 5 was installed in /opt/amazon/openmpi5
# ===================================================

# fi_info -p efa -t FI_EP_RDM
# Disable ptrace
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html
sudo sysctl -w kernel.yama.ptrace_scope=0


################################################################
## Install Flux and friends
#

# openpmix... back... back evil spirits!
sudo chown -R $USER /opt && \
    mkdir -p /opt/prrte && \
    cd /opt/prrte && \
    git clone https://github.com/openpmix/openpmix.git && \
    git clone https://github.com/openpmix/prrte.git && \
    set -x && \
    cd openpmix && \
    git checkout fefaed568f33bf86f28afb6e45237f1ec5e4de93 && \
    ./autogen.pl && \
    ./configure --prefix=/usr --disable-static && sudo make -j 4 install && \
    sudo ldconfig

# If you don't do this you get super fugly output the rest of the time.
set +x

# prrte you are sure looking perrrty today
cd /opt/prrte/prrte && \
    git checkout 477894f4720d822b15cab56eee7665107832921c && \
    ./autogen.pl && \
    ./configure --prefix=/usr && sudo make -j 4 install

# flux security
git clone --depth 1 https://github.com/flux-framework/flux-security /opt/flux-security && \
    cd /opt/flux-security && \
    ./autogen.sh && \
    PYTHON=/opt/conda/bin/python ./configure --prefix=/usr --sysconfdir=/etc && \
    make && sudo make install

# The VMs will share the same munge key
sudo mkdir -p /var/run/munge && \
    dd if=/dev/urandom bs=1 count=1024 > munge.key && \
    sudo mv munge.key /etc/munge/munge.key && \
    sudo chown -R munge /etc/munge/munge.key /var/run/munge && \
    sudo chmod 600 /etc/munge/munge.key

# Make the flux run directory
mkdir -p /home/ubuntu/run/flux

# Flux core
git clone https://github.com/flux-framework/flux-core /opt/flux-core && \
    cd /opt/flux-core && \
    ./autogen.sh && \
    PYTHON=/opt/conda/bin/python PYTHON_PREFIX=PYTHON_EXEC_PREFIX=/opt/conda/lib/python3.8/site-packages ./configure --prefix=/usr --sysconfdir=/etc --runstatedir=/home/flux/run --with-flux-security && \
    make clean && \
    make && sudo make install

# Flux pmix (must be installed after flux core)
git clone https://github.com/flux-framework/flux-pmix /opt/flux-pmix && \
  cd /opt/flux-pmix && \
  ./autogen.sh && \
  ./configure --prefix=/usr && \
  make && \
  sudo make install

# Flux sched
git clone https://github.com/flux-framework/flux-sched /opt/flux-sched && \
    cd /opt/flux-sched && \
    git fetch && \
    mkdir build && \
    cd build && \
    cmake ../ && make -j 4 && sudo make install && sudo ldconfig && \
    echo "DONE flux build"

# Flux curve.cert
# Ensure we have a shared curve certificate
flux keygen /tmp/curve.cert && \
    sudo mkdir -p /etc/flux/system && \
    sudo cp /tmp/curve.cert /etc/flux/system/curve.cert && \
    sudo chown ubuntu /etc/flux/system/curve.cert && \
    sudo chmod o-r /etc/flux/system/curve.cert && \
    sudo chmod g-r /etc/flux/system/curve.cert && \
    # Permissions for imp
    sudo chmod u+s /usr/libexec/flux/flux-imp && \
    sudo chmod 4755 /usr/libexec/flux/flux-imp && \
    # /var/lib/flux needs to be owned by the instance owner
    sudo mkdir -p /var/lib/flux && \
    sudo chown $USER -R /var/lib/flux && \
    # clean up (and make space)
    cd /
    sudo rm -rf /opt/flux-core /opt/flux-sched /opt/prrte /opt/flux-security


################################################################
## Build netmark
#
# https://github.com/converged-computing/operator-experiments/blob/4942e543438314c42fb6d2dc05e521297f95bc77/google/networking/netmark/run-job.py#L70

# Next you'll need to get netmark - I find scp from my local machine easiest
# You  probably don't need the option
scp -i ~/.ssh/your.pem -o IdentitiesOnly=yes -r netmark/ ubuntu@ec2-11-111-111-111.us-east-2.compute.amazonaws.com:/opt/netmark

# Then back in the instance...
cd /opt/netmark

# make sure mpicc is the one we want to use
export PATH=/opt/amazon/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/opt/amazon/openmpi/lib:/opt/amazon/openmpi/efa:$LD_LIBRARY_PATH
#  which mpicc
# /opt/amazon/openmpi/bin/mpicc 
# Note that I removed -lmpifort - I don't have it, and I don't know why we need to link fortran?
mpicc -lmpi -O3 netmark.c -DTRACE -I/opt/amazon/openmpi/include -I/opt/amazon/efa/include -L/opt/amazon/openmpi/lib -o netmark.x 
sudo cp netmark.x /usr/local/bin
sudo cp netmark.x /usr/local/bin/netmark

export VERSION="1.1.0" && \
curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_amd64.tar.gz" && \
mkdir -p oras-install/ && \
tar -zxf oras_${VERSION}_*.tar.gz -C oras-install/ && \
sudo mv oras-install/oras /usr/local/bin/ && \
rm -rf oras_${VERSION}_*.tar.gz oras-install/

# At this point we have what we need - save the ami in the interface, shut down (stop) or terminate.

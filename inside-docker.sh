#!/bin/bash

# This script is supposed to be run inside one of the manylinux
# docker image. It is a companion to the build-wheels script

# To build wheels for this project, call `build-wheels` after
# having customized this script

set -e -x

PROJ=$1

# Put here any build instructions for c extensions
# $ git clone ...
# $ cd ...
# $ ./configure && make && make install

yum install -y alsa-lib-devel
yum install -y jack-audio-connection-kit-devel


# Compile wheels. Customize the wildcard to match the desired python versions
for PYBIN in /opt/python/cp3{8,9,10}*/bin; do
    "${PYBIN}/pip" install --upgrade pip
    "${PYBIN}/pip" wheel /io/ -w wheelhouse/
done

# Bundle external shared libraries into the wheels
# for whl in wheelhouse/*.whl; do
for whl in wheelhouse/$PROJ*.whl; do
    auditwheel repair "$whl" --plat $PLAT -w /io/wheelhouse/
done 


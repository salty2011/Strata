#!/bin/bash
# Build upstream strata-dsv41 for gfx1100 on Fedora 44 (ROCm 7.1.1 from Fedora packages, no /opt/rocm).
# ~/rocm-shim gives an /opt/rocm-shaped root (lib/llvm -> /usr/lib64/rocm/llvm, bin/hipcc -> /usr/bin/hipcc).
set -e
cd ~/code/strata-up
R=$HOME/rocm-shim
B=build-dsv41-hip
if [ ! -f $B/build.ninja ]; then
cmake -S . -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_HIP=ON -DSTRATA_ENABLE_CUDA=OFF -DCMAKE_HIP_ARCHITECTURES=gfx1100 -DSTRATA_BUILD_TESTS=OFF -DSTRATA_BUILD_DSV41=ON -DSTRATA_NATIVE_EXPERTS=ON -DCMAKE_HIP_COMPILER=$R/lib/llvm/bin/clang++ -DCMAKE_PREFIX_PATH=$R -DCMAKE_EXE_LINKER_FLAGS=-no-pie "$@"
fi
nice -n 10 cmake --build $B -j ${JOBS:-12} --target strata-dsv41
echo BUILD-OK

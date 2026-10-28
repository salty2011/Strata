#!/bin/bash
# Fetch the small files upstream setup pins for the ISTA 2.00 set and verify sha256 against setup.py pins.
set -e
D=/srv/models/strata-up/deepseek-v4.1-flash-shared; cd $D
U=https://huggingface.co/unsloth/DeepSeek-V4.1-Flash-1017-GGUF/resolve/f924b94f19c1fea02c06a65c8475b0a45e2b88b1
curl -fL -C - -o DeepSeek-V4.1-Flash-1017-UD-Q8_K_XL-00001-of-00009.gguf $U/UD-Q8_K_XL/DeepSeek-V4.1-Flash-1017-UD-Q8_K_XL-00001-of-00009.gguf
curl -fL -C - -o mmproj-BF16.gguf $U/mmproj-BF16.gguf
curl -fL -C - -o dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf $U/dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf
cat > SHA256SUMS <<E2
cc15d470afcb030558bbc4d8e2ccd840182e2e95de1a95198138efe63a5fd99f  DeepSeek-V4.1-Flash-1017-UD-Q8_K_XL-00001-of-00009.gguf
9a1ef7c40d0d702c7ed8c5f863f60abae64091387ba3fce0ad19ce9beeda3bf9  mmproj-BF16.gguf
6ba6ac1b331c540691a209e7fc97dec2a24e295acb1e755c84c7d24a4373927a  dspark-DeepSeek-V4.1-Flash-1017-Q8_0.gguf
E2
sha256sum -c SHA256SUMS && echo DL-OK

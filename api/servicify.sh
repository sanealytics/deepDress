#!/bin/sh

export LD_LIBRARY_PATH=/usr/local/cudnn-v4/lib64:$LD_LIBRARY_PATH

RC=1
while [ $RC -ne 0 ]; do
   /home/ubuntu/torch/install/bin/th -i server.lua
   RC=$?
done

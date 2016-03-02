#!/bin/sh

RC=1
while [ $RC -ne 0 ]; do
   /home/ubuntu/torch/install/bin/th -i server.lua
   RC=$?
done

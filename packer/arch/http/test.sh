#!/usr/bin/env bash
set -eux
echo "✅ test.sh reached $(date)"
dmesg -n 8
printf "\n*** HELLO FROM test.sh ***\n\n"
sleep 10
systemctl poweroff -i

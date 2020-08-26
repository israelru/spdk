#!/usr/bin/env bash

LOG=$1

for s in "Req lat small," "Req lat large," "Req lat,"; do
    echo "$s"
    for i in $(seq 45); do
	grep "$s" $LOG | head -n $((i*32)) | tail -32 |  cut -d ":" -f 2 | awk '{s+=$1}END{print s/32}'
    done
done

#!/bin/bash

echo "Generating output for A6 paper"

dub -- --fontsize 40 -n 3 -f "in:b%s" -t "Lager %s" --base "ABCDEFGHIJKLMNOPQRSTUVWXYZ" -i 0
echo "Generated output for A6 paper, use 5mm border!"

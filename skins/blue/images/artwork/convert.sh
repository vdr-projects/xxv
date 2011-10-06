#!/bin/sh

FRAMES='180 200 400 600 800'

for i in $FRAMES; do

convert frame${i}.png  -crop ${i}x22+0+0  +repage ../head${i}.png
convert frame${i}.png  -crop ${i}x1+0+50  +repage ../mid${i}.png
convert frame${i}.png  -crop ${i}x15+0+85 +repage ../down${i}.png

done

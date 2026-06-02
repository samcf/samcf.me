#!/bin/sh
set -o errexit -o nounset

for src in post/*.md; do
    dst="docs/${src%.md}.html"

    printf '%s -> %s\n' "$src" "$dst"
    pandoc "$src"                \
      --syntax-highlighting=none \
      --template template.html   \
      --output "$dst"
done

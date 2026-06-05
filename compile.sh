#!/bin/sh
set -o errexit -o nounset

printf '%s -> %s\n' "index.md" "docs/index.html"
pandoc index.md            \
  --template template.html \
  --output docs/index.html

for src in post/*.md; do
    dst="docs/${src%.md}.html"

    printf '%s -> %s\n' "$src" "$dst"
    pandoc "$src"                \
      --syntax-highlighting=none \
      --template template.html   \
      --output "$dst"
done

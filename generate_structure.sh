#!/bin/bash

set -e

JQ=$(command -v jq)
[[ -z "$JQ" ]] && { echo "jq is required. Install it and rerun."; exit 1; }

STRUCTURE="./structure.json"
BOARDS_DIR="./boards"
PHOTOS_DIR="./photos"
MANUALS_DIR="./manuals"
ROOT_DIR="."

echo "🔄 Consolidating board folders..."

# Clean up duplicates by finding canonical name from JSON
for module in $(jq -r '.boards | keys[]' "$STRUCTURE"); do
  raw_name=$(jq -r ".boards[\"$module\"].name" "$STRUCTURE")
  clean_name=$(echo "${module}_${raw_name}" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/__/_/g')
  target="$BOARDS_DIR/$clean_name"
  mkdir -p "$target"

  echo "📁 Merging for $module → $clean_name"

  # Move photos and .mds from matching folders
  find "$BOARDS_DIR" -maxdepth 1 -type d -iname "${module}_*" ! -path "$target" | while read other; do
    mv "$other"/* "$target/" 2>/dev/null || true
    rmdir "$other" 2>/dev/null || true
  done

  # Generate markdown
  md="$target/${clean_name}.md"
  schematic=$(jq -r ".boards[\"$module\"].schematic" "$STRUCTURE")
  pcb=$(jq -r ".boards[\"$module\"].pcb" "$STRUCTURE")

  FRONT_IMG=$(find "$target" -iname "${module}_Front.jpg" | head -n1)
  BACK_IMG=$(find "$target" -iname "${module}_Back.jpg" | head -n1)

  echo "# $module — $raw_name" > "$md"
  echo "" >> "$md"
  echo "## [Function]" >> "$md"
  echo "Description from block diagram and manual." >> "$md"
  echo "" >> "$md"
  echo "## [Board Info]" >> "$md"
  echo "- Schematic number: $schematic" >> "$md"
  echo "- PC board number: $pcb" >> "$md"
  echo "" >> "$md"
  echo "## [Photos]" >> "$md"
  [[ -f "$FRONT_IMG" ]] && echo "![Front]($(basename "$FRONT_IMG"))" >> "$md"
  [[ -f "$BACK_IMG" ]] && echo "![Back]($(basename "$BACK_IMG"))" >> "$md"

  echo "" >> "$md"
  echo "<details><summary>More Images</summary>" >> "$md"
  echo "" >> "$md"
  find "$target" -iname "${module}_*.jpg" ! -iname "*Front.jpg" ! -iname "*Back.jpg" | sort | while read img; do
    echo "![Extra]($(basename "$img"))" >> "$md"
  done
  echo "</details>" >> "$md"
  echo "" >> "$md"
  echo "## [Debug]" >> "$md"
  echo "" >> "$md"
  echo "## [Findings]" >> "$md"
  echo "" >> "$md"
  echo "## [Comments]" >> "$md"
  echo "" >> "$md"
  echo "## [BOM]" >> "$md"
  echo "| Ref | Part | Description | Notes |" >> "$md"
  echo "|-----|------|-------------|-------|" >> "$md"
done

echo "🧩 Building overview.md..."

OVERVIEW="$ROOT_DIR/overview.md"
BLOCK_DIAGRAM=$(jq -r '.block_diagram' "$STRUCTURE")
MANUAL=$(jq -r '.manual' "$STRUCTURE")

echo "# Oscilloquartz 3200 Repair Overview" > "$OVERVIEW"
echo "" >> "$OVERVIEW"

# Instrument photos
echo "## Instrument Photos" >> "$OVERVIEW"
jq -r '.instrument_photos[]' "$STRUCTURE" | while read photo; do
  base=$(basename "$photo")
  echo "![${base}]($photo)" >> "$OVERVIEW"
done

echo "" >> "$OVERVIEW"
echo "## Block Diagram" >> "$OVERVIEW"
echo "![Block Diagram]($BLOCK_DIAGRAM)" >> "$OVERVIEW"
echo "" >> "$OVERVIEW"
echo "## 📖 Manual" >> "$OVERVIEW"
echo "[View manual]($MANUAL)" >> "$OVERVIEW"
echo "" >> "$OVERVIEW"

echo "## Boards" >> "$OVERVIEW"
echo "" >> "$OVERVIEW"
jq -r '.boards | to_entries[] | "- [\(.key) — \(.value.name)](boards/\(.key)_\(.value.name | gsub("[^a-zA-Z0-9]"; "_") | gsub("__"; "_"))/\(.key)_\(.value.name | gsub("[^a-zA-Z0-9]"; "_") | gsub("__"; "_")).md)"' "$STRUCTURE" >> "$OVERVIEW"

echo "✅ Flattened structure updated and ready."


#!/bin/bash

set -e

root_dir="Oscilloquartz-3200-Repair"
boards_dir="$root_dir/boards"
mkdir -p "$boards_dir"

cp -n 3200BlockDiagramm.png "$root_dir/" 2>/dev/null || true

declare -A module_names=(
  ["A1"]="Cesium oven supply"
  ["A2"]="Power supply +5V, -U ionizer, 26 kHz generator"
  ["A3"]="Power supply +U1, +U2, C-field, EMVH regulation, Pump alarm logic"
  ["A4"]="Buffer amplifier 5 MHz"
  ["A5"]="Synthesizer"
  ["A6"]="VCXO 12.631770 MHz"
  ["A7"]="Modulation generator, Quadrature detector"
  ["A8"]="Synchronous detector, Integrator, Summing"
  ["A9"]="Pre-amplifier, Servo amplifier"
  ["A10"]="2nd harmonic detector, Alarm logic"
)

declare -A schematic_numbers=(
  ["A1"]="942030002"
  ["A2"]="942030003"
  ["A3"]="942030010"
  ["A4"]="942030012"
  ["A5"]="942030011"
  ["A6"]="942030017"
  ["A7"]="942030008"
  ["A8"]="942030013"
  ["A9"]="942030007"
  ["A10"]="942030009"
)

declare -A pcb_numbers=(
  ["A1"]="956300015"
  ["A2"]="956300016"
  ["A3"]="956300020"
  ["A4"]="956300022"
  ["A5"]="956300021"
  ["A6"]="956300024"
  ["A7"]="956300018"
  ["A8"]="956300023"
  ["A9"]="956300017"
  ["A10"]="956300019"
)

# Overview generation
overview="$root_dir/overview.md"
echo "# Oscilloquartz 3200 Repair Documentation" > "$overview"
echo "" >> "$overview"
echo "![Block Diagram](3200BlockDiagramm.png)" >> "$overview"
echo "" >> "$overview"
echo "## Module Overview" >> "$overview"
echo "" >> "$overview"

# Board loop
for module in "${!module_names[@]}"; do
  name="${module_names[$module]}"
  schematic="${schematic_numbers[$module]}"
  pcb="${pcb_numbers[$module]}"
  safe_name=$(echo "${module}_${name}" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/__/_/g')
  folder="$boards_dir/$safe_name"
  mkdir -p "$folder"

  # Image placeholders
  [[ -f "$folder/${module}_Front.jpg" ]] || touch "$folder/${module}_Front.jpg"
  [[ -f "$folder/${module}_Back.jpg" ]] || touch "$folder/${module}_Back.jpg"

  # Markdown filename
  md_file="$folder/${safe_name}.md"

  # Only create if not yet present
  if [[ ! -f "$md_file" ]]; then
    cat <<EOF > "$md_file"
# $module — $name

## [Function]
Description from block diagram and manual.

## [Board Info]
- Schematic number: $schematic
- PC board number: $pcb

## [Debug]
*(Add debugging logs and results here)*

## [Findings]
*(Add reverse-engineered information here)*

## [Comments]
*(Freeform notes and repair hints)*

## [BOM]
| Ref | Part | Description | Notes |
|-----|------|-------------|-------|

## [Photos]
![Front view](${module}_Front.jpg)  
![Back view](${module}_Back.jpg)
EOF
  fi

  # Add to overview (skip if already listed)
  relative_path="boards/$safe_name/$(basename "$md_file")"
  grep -q "$relative_path" "$overview" || echo "- [$module — $name]($relative_path)" >> "$overview"
done

echo "✅ Folder structure and docs are ready in '$root_dir'"

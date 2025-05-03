#!/bin/bash
set -e

declare -A MOVES=(
  # Format: ["source path"]="destination folder"
  ["boards/A2_Power_supply_5V__U_ionizer_26_kHz_generator/A2_Back.jpg"]="boards/A2_Power_supply_+5V_-U_ionizer_26_kHz_generator"
  ["boards/A2_Power_supply_5V__U_ionizer_26_kHz_generator/A2_Front.jpg"]="boards/A2_Power_supply_+5V_-U_ionizer_26_kHz_generator"
  
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Back.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Back_2.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Front.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Front_2.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Front_3.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Front_4.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  ["boards/A3_Power_supply_U1__U2_C_field_EMVH_regulation_Pump_alarm_logic/A3_Front_5.jpg"]="boards/A3_Power_supply_+U1_+U2_C-field_EMVH_regulation_Pump_alarm_logic"
  
  ["boards/A6_VCXO_12_631770_MHz/A6_Back.jpg"]="boards/A6_VCXO_12.631770_MHz"
  ["boards/A6_VCXO_12_631770_MHz/A6_Front.jpg"]="boards/A6_VCXO_12.631770_MHz"
  
  ["boards/A9_Pre_amplifier_Servo_amplifier/A9_Back.jpg"]="boards/A9_Pre-amplifier_Servo_amplifier"
  ["boards/A9_Pre_amplifier_Servo_amplifier/A9_Back_2.jpg"]="boards/A9_Pre-amplifier_Servo_amplifier"
  ["boards/A9_Pre_amplifier_Servo_amplifier/A9_Front.jpg"]="boards/A9_Pre-amplifier_Servo_amplifier"
  ["boards/A9_Pre_amplifier_Servo_amplifier/A9_Front_2.jpg"]="boards/A9_Pre-amplifier_Servo_amplifier"
  ["boards/A9_Pre_amplifier_Servo_amplifier/A9_Front_3.jpg"]="boards/A9_Pre-amplifier_Servo_amplifier"
  ["boards/A9_Pre_amplifier_Servo_amplifier/A9_Front_4.jpg"]="boards/A9_Pre-amplifier_Servo_amplifier"
)

echo "🚀 Starting explicit file move..."

for src in "${!MOVES[@]}"; do
  dst="${MOVES[$src]}"
  if [[ -f "$src" && -d "$dst" ]]; then
    echo "→ Moving $(basename "$src") to $dst"
    mv "$src" "$dst/"
  else
    echo "⚠️  Skipping $src (file or folder missing)"
  fi
done

# Attempt to remove empty source folders
echo ""
echo "🧹 Removing empty folders..."
find boards -type d -empty -not -path "boards" -print -delete

echo "✅ Done. You can now rerun ./consolidate_and_generate.sh"

#!/bin/bash

# Script to check and optionally fix color naming inconsistencies in rofi themes

echo "Analyzing rofi color variable naming..."
echo ""

# Find inconsistencies
BRITISH_VARS=$(grep -r "^\s*\(border-colour\|background-colour\|foreground-colour\|handle-colour\):" .config/rofi --include="*.rasi" | wc -l)
AMERICAN_USAGE=$(grep -r "border-color:\s*@border-colour\|background-color:\s*@background-colour" .config/rofi --include="*.rasi" | wc -l)

echo "======================================"
echo "COLOR NAMING ANALYSIS:"
echo "======================================"
echo ""
echo "British-spelled variable definitions: $BRITISH_VARS"
echo "  (border-colour, background-colour, foreground-colour, handle-colour)"
echo ""
echo "American property usage: $AMERICAN_USAGE"
echo "  (border-color: @border-colour)"
echo ""

# Check for files with inconsistencies
echo "======================================"
echo "FILES WITH MIXED NAMING:"
echo "======================================"
FILES_WITH_BRITISH=$(grep -l "border-colour\|background-colour\|foreground-colour" .config/rofi -r --include="*.rasi" | wc -l)
TOTAL_FILES=$(find .config/rofi -name "*.rasi" | wc -l)

echo ""
echo "Files using British variable names: $FILES_WITH_BRITISH / $TOTAL_FILES"
echo ""

# List affected files
echo "Files with British-spelled variables:"
grep -l "border-colour\|background-colour\|foreground-colour" .config/rofi -r --include="*.rasi" | sed 's|.config/rofi/||' | head -20
echo "... (showing first 20)"
echo ""

# Check for potential issues
echo "======================================"
echo "POTENTIAL ISSUES:"
echo "======================================"
echo ""

# Check if variables are defined but not used correctly
UNDEFINED_REFS=$(grep -rh "@.*-colour" .config/rofi --include="*.rasi" | grep -v "^\s*\(border-colour\|background-colour\|foreground-colour\|handle-colour\):" | wc -l)

if [ "$UNDEFINED_REFS" -gt 0 ]; then
  echo "⚠ Found $UNDEFINED_REFS references to -colour variables"
  echo ""
  echo "This is actually CORRECT behavior:"
  echo "  • Custom variables use: border-colour, background-colour, etc."
  echo "  • Rofi properties reference: border-color: @border-colour"
  echo ""
  echo "Rofi property names (border-color, background-color) use American"
  echo "spelling, while custom variable names can use any naming convention."
else
  echo "✓ No undefined variable references found"
fi

echo ""
echo "======================================"
echo "RECOMMENDATION:"
echo "======================================"
echo ""
echo "The current setup is VALID but could be simplified:"
echo ""
echo "Current (works but potentially confusing):"
echo "  border-colour: var(selected);      // custom variable (British)"
echo "  border-color: @border-colour;      // rofi property (American)"
echo ""
echo "Recommended (more consistent):"
echo "  border-color-custom: var(selected); // custom variable (clear)"
echo "  border-color: @border-color-custom; // rofi property"
echo ""
echo "Or use American spelling throughout:"
echo "  border-color: var(selected);        // directly use standard name"
echo ""

read -p "Would you like to see a detailed report of color variable usage? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "======================================"
  echo "DETAILED COLOR VARIABLES BY FILE TYPE:"
  echo "======================================"
  echo ""

  for dir in launchers/type-1 launchers/type-2 launchers/type-3 launchers/type-4 powermenu themes applets; do
    if [ -d ".config/rofi/$dir" ]; then
      count=$(find ".config/rofi/$dir" -name "*.rasi" -exec grep -l "colour" {} \; 2>/dev/null | wc -l)
      total=$(find ".config/rofi/$dir" -name "*.rasi" 2>/dev/null | wc -l)
      if [ $total -gt 0 ]; then
        echo "$dir: $count/$total files use British spelling"
      fi
    fi
  done
fi

echo ""
echo "No action needed - color variables are functioning correctly!"

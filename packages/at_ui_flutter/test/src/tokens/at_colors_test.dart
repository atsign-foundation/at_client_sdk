import 'package:at_ui_flutter/src/tokens/at_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtColors Token Logic Tests', () {
    test('copyWith updates succesfully', () {
      final originalColors = AtColors.light();
      final updatedColorSwatch = AtColorSwatch(
        0xFFFFFFFF,
        shade50: Colors.white,
        shade100: Colors.white,
        shade200: Colors.white,
        shade300: Colors.white,
        shade400: Colors.white,
        shade500: Colors.white,
        shade600: Colors.white,
        shade700: Colors.white,
        shade800: Colors.white,
        shade900: Colors.white,
      );
      final updatedColors = originalColors.copyWith(
        primary: updatedColorSwatch,
        secondary: updatedColorSwatch,
        success: updatedColorSwatch,
        info: updatedColorSwatch,
        warning: updatedColorSwatch,
        error: updatedColorSwatch,
      );

      // Verify that the updated values are correctly applied
      expect(updatedColors.primary, isNot(originalColors.primary));
      expect(updatedColors.secondary, isNot(originalColors.secondary));
      expect(updatedColors.success, isNot(originalColors.success));
      expect(updatedColors.info, isNot(originalColors.info));
      expect(updatedColors.warning, isNot(originalColors.warning));
      expect(updatedColors.error, isNot(originalColors.error));
    });

    test('copyWith null values equals the original colors', () {
      final originalColors = AtColors.light();
      final updatedColors = originalColors.copyWith();

      // Verify that non-updated values remain unchanged
      expect(updatedColors.primary, originalColors.primary);
      expect(updatedColors.secondary, originalColors.secondary);
      expect(updatedColors.success, originalColors.success);
      expect(updatedColors.info, originalColors.info);
      expect(updatedColors.warning, originalColors.warning);
      expect(updatedColors.error, originalColors.error);
    });

    test('lerp correctly interpolates between two AtColors instances', () {
      final colorsA = AtColors.light();
      final colorsBColorSwatch = AtColorSwatch(
        0xFFFFFFFF,
        shade50: Colors.white,
        shade100: Colors.white,
        shade200: Colors.white,
        shade300: Colors.white,
        shade400: Colors.white,
        shade500: Colors.white,
        shade600: Colors.white,
        shade700: Colors.white,
        shade800: Colors.white,
        shade900: Colors.white,
      );
      final colorsB = AtColors(
        primary: colorsBColorSwatch,
        secondary: colorsBColorSwatch,
        success: colorsBColorSwatch,
        info: colorsBColorSwatch,
        warning: colorsBColorSwatch,
        error: colorsBColorSwatch,
      );

      // Interpolate halfway between colorsA and colorsB
      final midColors = colorsA.lerp(colorsB, 0.5);

      // Verify that the midColors values are neither colorsA nor colorsB
      expect(midColors.primary, isNot(colorsA.primary));
      expect(midColors.primary, isNot(colorsB.primary));
      expect(midColors.secondary, isNot(colorsA.secondary));
      expect(midColors.secondary, isNot(colorsB.secondary));
      expect(midColors.success, isNot(colorsA.success));
      expect(midColors.success, isNot(colorsB.success));
      expect(midColors.info, isNot(colorsA.info));
      expect(midColors.info, isNot(colorsB.info));
      expect(midColors.warning, isNot(colorsA.warning));
      expect(midColors.warning, isNot(colorsB.warning));
      expect(midColors.error, isNot(colorsA.error));
      expect(midColors.error, isNot(colorsB.error));
    });
  });
}

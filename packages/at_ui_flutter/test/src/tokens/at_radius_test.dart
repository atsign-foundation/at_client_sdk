import 'package:at_ui_flutter/src/tokens/at_radius.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('at radius ...', () {
    test('copyWith successfully overrides specific values', () {
      const originalRadius = AtRadius();
      final updatedRadius = originalRadius.copyWith(
        none: 1.0,
        xs: originalRadius.xs * 2,
        sm: originalRadius.sm * 2,
        md: originalRadius.md * 2,
        lg: originalRadius.lg * 2,
        xl: originalRadius.xl * 2,
        x2l: originalRadius.x2l * 2,
        x3l: originalRadius.x3l * 2,
        full: originalRadius.full * 2,
      );
      // Verify that the updated values are correctly applied
      expect(updatedRadius.none, 1.0);
      expect(updatedRadius.xs, originalRadius.xs * 2);
      expect(updatedRadius.sm, originalRadius.sm * 2);
      expect(updatedRadius.md, originalRadius.md * 2);
      expect(updatedRadius.lg, originalRadius.lg * 2);
      expect(updatedRadius.xl, originalRadius.xl * 2);
      expect(updatedRadius.x2l, originalRadius.x2l * 2);
      expect(updatedRadius.x3l, originalRadius.x3l * 2);
      expect(updatedRadius.full, originalRadius.full * 2);
      expect(updatedRadius, isNot(originalRadius));
    });

    test('copyWith null values equals the original radius', () {
      const originalRadius = AtRadius();
      final updatedRadius = originalRadius.copyWith();

      // Verify that non-updated values remain unchanged
      expect(updatedRadius, originalRadius);
    });

    test('lerp correctly interpolates between two AtRadius instances', () {
      const radiusA = AtRadius();
      final radiusB = AtRadius(
        none: 1.0,
        xs: radiusA.xs * 2,
        sm: radiusA.sm * 2,
        md: radiusA.md * 2,
        lg: radiusA.lg * 2,
        xl: radiusA.xl * 2,
        x2l: radiusA.x2l * 2,
        x3l: radiusA.x3l * 2,
        full: radiusA.full * 2,
      );
      // Interpolate halfway between radiusA and radiusB
      final midRadius = radiusA.lerp(radiusB, 0.5);

      // Verify that the midRadius values are the average of radiusA and radiusB
      expect(midRadius.none, 0.5);
      expect(midRadius.xs, (radiusA.xs + (radiusA.xs * 2)) / 2);
      expect(midRadius.sm, (radiusA.sm + (radiusA.sm * 2)) / 2);
      expect(midRadius.md, (radiusA.md + (radiusA.md * 2)) / 2);
      expect(midRadius.lg, (radiusA.lg + (radiusA.lg * 2)) / 2);
      expect(midRadius.xl, (radiusA.xl + (radiusA.xl * 2)) / 2);
      expect(midRadius.x2l, (radiusA.x2l + (radiusA.x2l * 2)) / 2);
      expect(midRadius.x3l, (radiusA.x3l + (radiusA.x3l * 2)) / 2);
      expect(midRadius.full, (radiusA.full + (radiusA.full * 2)) / 2);
    });
  });
}

import 'package:at_ui_flutter/src/tokens/at_radius.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('at radius ...', () {
    test('copyWith successfully overrides specific values', () {
      const originalRadius = AtRadius();
      final updatedRadius = originalRadius.copyWith(
        radiusNone: 1.0,
        radiusXs: originalRadius.radiusXs * 2,
        radiusSm: originalRadius.radiusSm * 2,
        radiusMd: originalRadius.radiusMd * 2,
        radiusLg: originalRadius.radiusLg * 2,
        radiusXl: originalRadius.radiusXl * 2,
        radius2xl: originalRadius.radius2xl * 2,
        radius3xl: originalRadius.radius3xl * 2,
        radiusFull: originalRadius.radiusFull * 2,
      );
      // Verify that the updated values are correctly applied
      expect(updatedRadius.radiusNone, 1.0);
      expect(updatedRadius.radiusXs, originalRadius.radiusXs * 2);
      expect(updatedRadius.radiusSm, originalRadius.radiusSm * 2);
      expect(updatedRadius.radiusMd, originalRadius.radiusMd * 2);
      expect(updatedRadius.radiusLg, originalRadius.radiusLg * 2);
      expect(updatedRadius.radiusXl, originalRadius.radiusXl * 2);
      expect(updatedRadius.radius2xl, originalRadius.radius2xl * 2);
      expect(updatedRadius.radius3xl, originalRadius.radius3xl * 2);
      expect(updatedRadius.radiusFull, originalRadius.radiusFull * 2);
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
        radiusNone: 1.0,
        radiusXs: radiusA.radiusXs * 2,
        radiusSm: radiusA.radiusSm * 2,
        radiusMd: radiusA.radiusMd * 2,
        radiusLg: radiusA.radiusLg * 2,
        radiusXl: radiusA.radiusXl * 2,
        radius2xl: radiusA.radius2xl * 2,
        radius3xl: radiusA.radius3xl * 2,
        radiusFull: radiusA.radiusFull * 2,
      );
      // Interpolate halfway between radiusA and radiusB
      final midRadius = radiusA.lerp(radiusB, 0.5);

      // Verify that the midRadius values are the average of radiusA and radiusB
      expect(midRadius.radiusNone, 0.5);
      expect(
        midRadius.radiusXs,
        (radiusA.radiusXs + (radiusA.radiusXs * 2)) / 2,
      );
      expect(
        midRadius.radiusSm,
        (radiusA.radiusSm + (radiusA.radiusSm * 2)) / 2,
      );
      expect(
        midRadius.radiusMd,
        (radiusA.radiusMd + (radiusA.radiusMd * 2)) / 2,
      );
      expect(
        midRadius.radiusLg,
        (radiusA.radiusLg + (radiusA.radiusLg * 2)) / 2,
      );
      expect(
        midRadius.radiusXl,
        (radiusA.radiusXl + (radiusA.radiusXl * 2)) / 2,
      );
      expect(
        midRadius.radius2xl,
        (radiusA.radius2xl + (radiusA.radius2xl * 2)) / 2,
      );
      expect(
        midRadius.radius3xl,
        (radiusA.radius3xl + (radiusA.radius3xl * 2)) / 2,
      );
      expect(
        midRadius.radiusFull,
        (radiusA.radiusFull + (radiusA.radiusFull * 2)) / 2,
      );
    });
  });
}

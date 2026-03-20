import 'package:at_ui_flutter/at_ui_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('at spacing ...', () {
    group('AtSpacing Token Logic Tests', () {
      test('copyWith successfully overrides specific values', () {
        const originalSpacing = AtSpacing();

        var updatedSpacing = originalSpacing.copyWith(
          scale2: 102.0,
          scale4: 104.0,
          scale6: 106.0,
          scale8: 108.0,
          scale12: 112.0,
          scale16: 116.0,
          scale20: 120.0,
          scale24: 124.0,
          scale32: 132.0,
          scale36: 136.0,
          scale40: 140.0,
          scale48: 148.0,
        );
        // Verify that the updated values are correctly applied
        expect(updatedSpacing.scale2, 102.0);
        expect(updatedSpacing.scale4, 104.0);
        expect(updatedSpacing.scale6, 106.0);
        expect(updatedSpacing.scale8, 108.0);
        expect(updatedSpacing.scale12, 112.0);
        expect(updatedSpacing.scale16, 116.0);
        expect(updatedSpacing.scale20, 120.0);
        expect(updatedSpacing.scale24, 124.0);
        expect(updatedSpacing.scale32, 132.0);
        expect(updatedSpacing.scale36, 136.0);
        expect(updatedSpacing.scale40, 140.0);
        expect(updatedSpacing.scale48, 148.0);
        expect(updatedSpacing, isNot(originalSpacing));
      });
      test('copyWith null values equals the original spacing', () {
        const originalSpacing = AtSpacing();
        final updatedSpacing = originalSpacing.copyWith();

        // Verify that non-updated values remain unchanged
        expect(updatedSpacing, originalSpacing);
      });

      test('lerp correctly interpolates between two AtSpacing instances', () {
        const spacingA = AtSpacing();
        const spacingB = AtSpacing(
          scale2: 200.0,
          scale4: 400.0,
          scale6: 600.0,
          scale8: 800.0,
          scale12: 1200.0,
          scale16: 1600.0,
          scale20: 2000.0,
          scale24: 2400.0,
          scale32: 3200.0,
          scale36: 3600.0,
          scale40: 4000.0,
          scale48: 4800.0,
        );
        // Interpolate halfway between spacingA and spacingB
        final midSpacing = spacingA.lerp(spacingB, 0.5);

        // Verify that the midSpacing values are the average of spacingA and spacingB
        expect(midSpacing.scale2, (spacingA.scale2 + spacingB.scale2) / 2);
        expect(midSpacing.scale4, (spacingA.scale4 + spacingB.scale4) / 2);
        expect(midSpacing.scale6, (spacingA.scale6 + spacingB.scale6) / 2);
        expect(midSpacing.scale8, (spacingA.scale8 + spacingB.scale8) / 2);
        expect(midSpacing.scale12, (spacingA.scale12 + spacingB.scale12) / 2);
        expect(midSpacing.scale16, (spacingA.scale16 + spacingB.scale16) / 2);
        expect(midSpacing.scale20, (spacingA.scale20 + spacingB.scale20) / 2);
        expect(midSpacing.scale24, (spacingA.scale24 + spacingB.scale24) / 2);
        expect(midSpacing.scale32, (spacingA.scale32 + spacingB.scale32) / 2);
        expect(midSpacing.scale36, (spacingA.scale36 + spacingB.scale36) / 2);
        expect(midSpacing.scale40, (spacingA.scale40 + spacingB.scale40) / 2);
        expect(midSpacing.scale48, (spacingA.scale48 + spacingB.scale48) / 2);
      });
    });
  });
}

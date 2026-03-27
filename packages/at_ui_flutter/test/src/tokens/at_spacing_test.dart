import 'package:at_ui_flutter/at_ui_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('at spacing ...', () {
    group('AtSpacing Token Logic Tests', () {
      test('copyWith successfully overrides specific values', () {
        const originalSpacing = AtSpacing();
        final updatedSpacing = originalSpacing.copyWith(
          s2: 102.0,
          s4: 104.0,
          s6: 106.0,
          s8: 108.0,
          s12: 112.0,
          s16: 116.0,
          s20: 120.0,
          s24: 124.0,
          s32: 132.0,
          s36: 136.0,
          s40: 140.0,
          s48: 148.0,
        );
        // Verify that the updated values are correctly applied
        expect(updatedSpacing.s2, 102.0);
        expect(updatedSpacing.s4, 104.0);
        expect(updatedSpacing.s6, 106.0);
        expect(updatedSpacing.s8, 108.0);
        expect(updatedSpacing.s12, 112.0);
        expect(updatedSpacing.s16, 116.0);
        expect(updatedSpacing.s20, 120.0);
        expect(updatedSpacing.s24, 124.0);
        expect(updatedSpacing.s32, 132.0);
        expect(updatedSpacing.s36, 136.0);
        expect(updatedSpacing.s40, 140.0);
        expect(updatedSpacing.s48, 148.0);
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
          s2: 200.0,
          s4: 400.0,
          s6: 600.0,
          s8: 800.0,
          s12: 1200.0,
          s16: 1600.0,
          s20: 2000.0,
          s24: 2400.0,
          s32: 3200.0,
          s36: 3600.0,
          s40: 4000.0,
          s48: 4800.0,
        );
        // Interpolate halfway between spacingA and spacingB
        final midSpacing = spacingA.lerp(spacingB, 0.5);

        // Verify that the midSpacing values are the average of spacingA and spacingB
        expect(midSpacing.s2, (spacingA.s2 + spacingB.s2) / 2);
        expect(midSpacing.s4, (spacingA.s4 + spacingB.s4) / 2);
        expect(midSpacing.s6, (spacingA.s6 + spacingB.s6) / 2);
        expect(midSpacing.s8, (spacingA.s8 + spacingB.s8) / 2);
        expect(midSpacing.s12, (spacingA.s12 + spacingB.s12) / 2);
        expect(midSpacing.s16, (spacingA.s16 + spacingB.s16) / 2);
        expect(midSpacing.s20, (spacingA.s20 + spacingB.s20) / 2);
        expect(midSpacing.s24, (spacingA.s24 + spacingB.s24) / 2);
        expect(midSpacing.s32, (spacingA.s32 + spacingB.s32) / 2);
        expect(midSpacing.s36, (spacingA.s36 + spacingB.s36) / 2);
        expect(midSpacing.s40, (spacingA.s40 + spacingB.s40) / 2);
        expect(midSpacing.s48, (spacingA.s48 + spacingB.s48) / 2);
      });
    });
  });
}

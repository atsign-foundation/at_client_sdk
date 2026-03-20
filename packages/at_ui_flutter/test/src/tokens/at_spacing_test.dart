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
    });
  });
}

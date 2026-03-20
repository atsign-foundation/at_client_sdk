import 'package:at_ui_flutter/src/tokens/at_elevation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('at elevation ...', () {
    test('copyWith Successfully Overrides specific values', () {
      final originalElevation = AtElevation.standard();
      final updatedBoxShadow = [
        const BoxShadow(
          color: Colors.white,
          offset: Offset(0, 0),
          blurRadius: 0,
        ),
      ];
      final updatedElevation = originalElevation.copyWith(
        neutral0: updatedBoxShadow,
        neutral1: updatedBoxShadow,
        neutral2: updatedBoxShadow,
        neutral3: updatedBoxShadow,
        neutral4: updatedBoxShadow,
        neutral5: updatedBoxShadow,
        semantic0: updatedBoxShadow,
        semantic1: updatedBoxShadow,
        semantic2: updatedBoxShadow,
        semantic3: updatedBoxShadow,
        semantic4: updatedBoxShadow,
        semantic5: updatedBoxShadow,
      );
      // Verify that the updated values are correctly applied
      expect(updatedElevation.neutral0, updatedBoxShadow);
      expect(updatedElevation.neutral1, updatedBoxShadow);
      expect(updatedElevation.neutral2, updatedBoxShadow);
      expect(updatedElevation.neutral3, updatedBoxShadow);
      expect(updatedElevation.neutral4, updatedBoxShadow);
      expect(updatedElevation.neutral5, updatedBoxShadow);
      expect(updatedElevation.semantic0, updatedBoxShadow);
      expect(updatedElevation.semantic1, updatedBoxShadow);
      expect(updatedElevation.semantic2, updatedBoxShadow);
      expect(updatedElevation.semantic3, updatedBoxShadow);
      expect(updatedElevation.semantic4, updatedBoxShadow);
      expect(updatedElevation.semantic5, updatedBoxShadow);
    });

    test('copyWith null values equals the original elevation', () {
      final originalElevation = AtElevation.standard();
      final updatedElevation = originalElevation.copyWith();

      // Verify that non-updated values remain unchanged
      expect(updatedElevation.neutral0, originalElevation.neutral0);
      expect(updatedElevation.neutral1, originalElevation.neutral1);
      expect(updatedElevation.neutral2, originalElevation.neutral2);
      expect(updatedElevation.neutral3, originalElevation.neutral3);
      expect(updatedElevation.neutral4, originalElevation.neutral4);
      expect(updatedElevation.neutral5, originalElevation.neutral5);
      expect(updatedElevation.semantic0, originalElevation.semantic0);
      expect(updatedElevation.semantic1, originalElevation.semantic1);
      expect(updatedElevation.semantic2, originalElevation.semantic2);
      expect(updatedElevation.semantic3, originalElevation.semantic3);
      expect(updatedElevation.semantic4, originalElevation.semantic4);
      expect(updatedElevation.semantic5, originalElevation.semantic5);
    });

    test('lerp correctly interpolates between two AtElevation instances', () {
      final elevationA = AtElevation.standard();
      const elevationBBoxShadow = [
        BoxShadow(
          color: Colors.indigoAccent,
          offset: Offset(0, 0),
          blurRadius: 0,
        ),
      ];
      final elevationB = AtElevation(
        neutral0: elevationBBoxShadow,
        neutral1: elevationBBoxShadow,
        neutral2: elevationBBoxShadow,
        neutral3: elevationBBoxShadow,
        neutral4: elevationBBoxShadow,
        neutral5: elevationBBoxShadow,
        semantic0: elevationBBoxShadow,
        semantic1: elevationBBoxShadow,
        semantic2: elevationBBoxShadow,
        semantic3: elevationBBoxShadow,
        semantic4: elevationBBoxShadow,
        semantic5: elevationBBoxShadow,
      );

      // Interpolate halfway between elevationA and elevationB
      final midElevation = elevationA.lerp(elevationB, 0.5);
      // Verify that the midElevation values are neither exactly elevationA nor elevationB.
      expect(midElevation.neutral0, isNot(elevationA.neutral0));
      expect(
        midElevation.neutral0,
        elevationB.neutral0,
      ); // In Empty list all lerp values are the same as 1.
      expect(midElevation.neutral1, isNot(elevationA.neutral1));
      expect(midElevation.neutral1, isNot(elevationB.neutral1));
      expect(midElevation.neutral2, isNot(elevationA.neutral2));
      expect(midElevation.neutral2, isNot(elevationB.neutral2));
      expect(midElevation.neutral3, isNot(elevationA.neutral3));
      expect(midElevation.neutral3, isNot(elevationB.neutral3));
      expect(midElevation.neutral4, isNot(elevationA.neutral4));
      expect(midElevation.neutral4, isNot(elevationB.neutral4));
      expect(midElevation.neutral5, isNot(elevationA.neutral5));
      expect(midElevation.neutral5, isNot(elevationB.neutral5));
      expect(midElevation.semantic0, isNot(elevationA.semantic0));
      expect(
        midElevation.semantic0,
        elevationB.semantic0,
      ); // In Empty list all lerp values are the same as 1.
      expect(midElevation.semantic1, isNot(elevationA.semantic1));
      expect(midElevation.semantic1, isNot(elevationB.semantic1));
      expect(midElevation.semantic2, isNot(elevationA.semantic2));
      expect(midElevation.semantic2, isNot(elevationB.semantic2));
      expect(midElevation.semantic3, isNot(elevationA.semantic3));
      expect(midElevation.semantic3, isNot(elevationB.semantic3));
      expect(midElevation.semantic4, isNot(elevationA.semantic4));
      expect(midElevation.semantic4, isNot(elevationB.semantic4));
      expect(midElevation.semantic5, isNot(elevationA.semantic5));
      expect(midElevation.semantic5, isNot(elevationB.semantic5));
    });
  });
}

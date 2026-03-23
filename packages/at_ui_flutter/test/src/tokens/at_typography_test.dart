import 'package:at_ui_flutter/src/tokens/at_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('at typography ...', () {
    test('copyWith successfully overrides specific values', () {
      final originalTypography = AtTypography.standard();
      const updatedTypographyTextStyle = TextStyle(
        fontFamily: 'Roboto',
        package: 'at_ui_flutter',
        fontSize: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.0,
        height: 0,
      );
      final updatedTypography = originalTypography.copyWith(
        h1: updatedTypographyTextStyle,
        h2: updatedTypographyTextStyle,
        h3: updatedTypographyTextStyle,
        h4: updatedTypographyTextStyle,
        bodyLgRegular: updatedTypographyTextStyle,
        bodyMdRegular: updatedTypographyTextStyle,
        bodySmRegular: updatedTypographyTextStyle,
        buttonMd: updatedTypographyTextStyle,
      );
      // Verify that the updated values are correctly applied
      expect(
        updatedTypography.h1.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.h2.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.h3.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.h4.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.bodyLgRegular.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.bodyMdRegular.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.bodySmRegular.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(
        updatedTypography.buttonMd.fontSize,
        updatedTypographyTextStyle.fontSize,
      );
      expect(updatedTypography, isNot(originalTypography));
    });

    test('lerp correctly interpolates between two AtTypography instances', () {
      final typographyA = AtTypography.standard();
      const typographyBTextStyle = TextStyle(
        fontFamily: 'Roboto',
        fontSize: 1,
        fontWeight: FontWeight.w100,
        letterSpacing: 0.1,
        height: 0.1,
      );
      const typographyB = AtTypography(
        h1: typographyBTextStyle,
        h2: typographyBTextStyle,
        h3: typographyBTextStyle,
        h4: typographyBTextStyle,
        bodyLgSemiBold: typographyBTextStyle,
        bodyLgMedium: typographyBTextStyle,
        bodyLgRegular: typographyBTextStyle,
        bodyMdSemiBold: typographyBTextStyle,
        bodyMdMedium: typographyBTextStyle,
        bodyMdRegular: typographyBTextStyle,
        bodySmSemiBold: typographyBTextStyle,
        bodySmMedium: typographyBTextStyle,
        bodySmRegular: typographyBTextStyle,
        bodyXsSemiBold: typographyBTextStyle,
        bodyXsMedium: typographyBTextStyle,
        bodyXsRegular: typographyBTextStyle,
        bodyXxsSemiBold: typographyBTextStyle,
        bodyXxsMedium: typographyBTextStyle,
        bodyXxsRegular: typographyBTextStyle,
        buttonXl: typographyBTextStyle,
        buttonLg: typographyBTextStyle,
        buttonMd: typographyBTextStyle,
        buttonSm: typographyBTextStyle,
        buttonXs: typographyBTextStyle,
      );

      final midTypography = typographyA.lerp(typographyB, 0.5);

      // Verify that the midTypography has interpolated font sizes
      expect(midTypography.h1, isNot(typographyA.h1));
      expect(midTypography.h1, isNot(typographyB.h1));
      expect(midTypography.h2, isNot(typographyA.h2));
      expect(midTypography.h2, isNot(typographyB.h2));
      expect(midTypography.h3, isNot(typographyA.h3));
      expect(midTypography.h3, isNot(typographyB.h3));
      expect(midTypography.h4, isNot(typographyA.h4));
      expect(midTypography.h4, isNot(typographyB.h4));
      expect(midTypography.bodyLgSemiBold, isNot(typographyA.bodyLgSemiBold));
      expect(midTypography.bodyLgSemiBold, isNot(typographyB.bodyLgSemiBold));
      expect(midTypography.bodyLgMedium, isNot(typographyA.bodyLgMedium));
      expect(midTypography.bodyLgMedium, isNot(typographyB.bodyLgMedium));
      expect(midTypography.bodyLgRegular, isNot(typographyA.bodyLgRegular));
      expect(midTypography.bodyLgRegular, isNot(typographyB.bodyLgRegular));
      expect(midTypography.bodyMdSemiBold, isNot(typographyA.bodyMdSemiBold));
      expect(midTypography.bodyMdSemiBold, isNot(typographyB.bodyMdSemiBold));
      expect(midTypography.bodyMdMedium, isNot(typographyA.bodyMdMedium));
      expect(midTypography.bodyMdMedium, isNot(typographyB.bodyMdMedium));
      expect(midTypography.bodyMdRegular, isNot(typographyA.bodyMdRegular));
      expect(midTypography.bodyMdRegular, isNot(typographyB.bodyMdRegular));
      expect(midTypography.bodySmSemiBold, isNot(typographyA.bodySmSemiBold));
      expect(midTypography.bodySmSemiBold, isNot(typographyB.bodySmSemiBold));
      expect(midTypography.bodySmMedium, isNot(typographyA.bodySmMedium));
      expect(midTypography.bodySmMedium, isNot(typographyB.bodySmMedium));
      expect(midTypography.bodySmRegular, isNot(typographyA.bodySmRegular));
      expect(midTypography.bodySmRegular, isNot(typographyB.bodySmRegular));
      expect(midTypography.bodyXsSemiBold, isNot(typographyA.bodyXsSemiBold));
      expect(midTypography.bodyXsSemiBold, isNot(typographyB.bodyXsSemiBold));
      expect(midTypography.bodyXsMedium, isNot(typographyA.bodyXsMedium));
      expect(midTypography.bodyXsMedium, isNot(typographyB.bodyXsMedium));
      expect(midTypography.bodyXsRegular, isNot(typographyA.bodyXsRegular));
      expect(midTypography.bodyXsRegular, isNot(typographyB.bodyXsRegular));
      expect(midTypography.buttonXl, isNot(typographyA.buttonXl));
      expect(midTypography.buttonXl, isNot(typographyB.buttonXl));
      expect(midTypography.buttonLg, isNot(typographyA.buttonLg));
      expect(midTypography.buttonLg, isNot(typographyB.buttonLg));
      expect(midTypography.buttonMd, isNot(typographyA.buttonMd));
      expect(midTypography.buttonMd, isNot(typographyB.buttonMd));
      expect(midTypography.buttonSm, isNot(typographyA.buttonSm));
      expect(midTypography.buttonSm, isNot(typographyB.buttonSm));
      expect(midTypography.buttonXs, isNot(typographyA.buttonXs));
      expect(midTypography.buttonXs, isNot(typographyB.buttonXs));
    });
  });
}

import 'package:at_ui_flutter/at_ui_flutter.dart';
import 'package:at_ui_flutter/src/utils.dart/at_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtGap Utility Tests ...', () {
    const spacing = AtSpacing();

    test(
      'Height gaps (h) perfectly match AtSpacing scale and have no width',
      () {
        // Test height gaps
        expect(AtGap.h2.height, spacing.s2);
        expect(AtGap.h2.width, null);
        expect(AtGap.h4.height, spacing.s4);
        expect(AtGap.h4.width, null);
        expect(AtGap.h6.height, spacing.s6);
        expect(AtGap.h6.width, null);
        expect(AtGap.h8.height, spacing.s8);
        expect(AtGap.h8.width, null);
        expect(AtGap.h12.height, spacing.s12);
        expect(AtGap.h12.width, null);
        expect(AtGap.h16.height, spacing.s16);
        expect(AtGap.h16.width, null);
        expect(AtGap.h20.height, spacing.s20);
        expect(AtGap.h20.width, null);
        expect(AtGap.h24.height, spacing.s24);
        expect(AtGap.h24.width, null);
        expect(AtGap.h32.height, spacing.s32);
        expect(AtGap.h32.width, null);
        expect(AtGap.h36.height, spacing.s36);
        expect(AtGap.h36.width, null);
        expect(AtGap.h40.height, spacing.s40);
        expect(AtGap.h40.width, null);
        expect(AtGap.h48.height, spacing.s48);
        expect(AtGap.h48.width, null);
      },
    );
    test(
      'Width gaps (w) perfectly match AtSpacing scale and have no height',
      () {
        // Test width gaps
        expect(AtGap.w2.width, spacing.s2);
        expect(AtGap.w2.height, null);
        expect(AtGap.w4.width, spacing.s4);
        expect(AtGap.w4.height, null);
        expect(AtGap.w6.width, spacing.s6);
        expect(AtGap.w6.height, null);
        expect(AtGap.w8.width, spacing.s8);
        expect(AtGap.w8.height, null);
        expect(AtGap.w12.width, spacing.s12);
        expect(AtGap.w12.height, null);
        expect(AtGap.w16.width, spacing.s16);
        expect(AtGap.w16.height, null);
        expect(AtGap.w20.width, spacing.s20);
        expect(AtGap.w20.height, null);
        expect(AtGap.w24.width, spacing.s24);
        expect(AtGap.w24.height, null);
        expect(AtGap.w32.width, spacing.s32);
        expect(AtGap.w32.height, null);
        expect(AtGap.w36.width, spacing.s36);
        expect(AtGap.w36.height, null);
        expect(AtGap.w40.width, spacing.s40);
        expect(AtGap.w40.height, null);
        expect(AtGap.w48.width, spacing.s48);
        expect(AtGap.w48.height, null);
      },
    );
  });
}

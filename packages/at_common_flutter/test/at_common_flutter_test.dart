import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("get_width_ratio", () {
    SizeConfig().screenWidth = 1100;
    var res = SizeConfig().getWidthRatio(20);
    expect(res, 20);
  });

  test("get_height_ratio", () {
    SizeConfig().screenWidth = 1100;
    var res = SizeConfig().getHeightRatio(20);
    expect(res, 20);
  });

  test("get_font_ratio", () {
    SizeConfig().screenWidth = 1100;
    var res = SizeConfig().getFontRatio(20);
    expect(res, 20);
  });
}

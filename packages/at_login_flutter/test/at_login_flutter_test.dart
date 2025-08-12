import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// import 'package:at_login_flutter/at_login_flutter.dart';

void main() {
  const MethodChannel channel = MethodChannel('at_login_flutter');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      null,
    );
  });
}

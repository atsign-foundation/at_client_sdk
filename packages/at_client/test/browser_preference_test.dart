import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

void main() {
  test('the browser preset resumes in memory, never from a stored watermark',
      () {
    expect(AtClientPreference().fetchOfflineNotifications, isTrue,
        reason: 'the control: native keeps replaying from the store');
    expect(AtClientPreference.browser().fetchOfflineNotifications, isFalse);
  });
}

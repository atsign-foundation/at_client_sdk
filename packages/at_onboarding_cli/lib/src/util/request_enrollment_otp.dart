import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:duration/duration.dart';

Future<String> requestEnrollmentOtp(AtClient atClient, {String? otpExpiry}) async {
  StringBuffer otpCommandBuffer = StringBuffer()..append('otp:get');
  if (otpExpiry != null && otpExpiry.isNotEmpty) {
    otpCommandBuffer.append(':ttl:${parseDuration(otpExpiry).inMilliseconds}');
  }
  otpCommandBuffer.append('\n');

  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;
  // send command 'otp:get[:ttl:$ttl]'
  String? response =
      await atLookup.executeCommand(otpCommandBuffer.getData()!, auth: true);
  if (response == null || !response.startsWith('data:')) {
    throw AtEnrollmentException(
        'Failed to generate OTP: server response was \'$response\'');
  }
  return response.substring('data:'.length);
}

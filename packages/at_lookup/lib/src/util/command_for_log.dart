final _otpPut = RegExp(r'^(otp:put:)(.*?)(:ttl:\d+)?(\s*)$', dotAll: true);
final _enrollOtp = RegExp(r'("otp"\s*:\s*")((?:[^"\\]|\\.)*)(")');

/// [command] as a log line shows it: the passcode an `otp:put` sets and the
/// `otp` an `enroll:` command carries are written as `***`, and any other
/// command as it is.
String commandForLog(String command) {
  if (command.startsWith('otp:put:')) {
    return command.replaceFirstMapped(
        _otpPut, (m) => '${m[1]}***${m[3] ?? ''}${m[4]}');
  }
  if (command.startsWith('enroll:')) {
    return command.replaceAllMapped(_enrollOtp, (m) => '${m[1]}***${m[3]}');
  }
  return command;
}

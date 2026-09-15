/// Why the atServer refused a connection's credentials: the enrollment it
/// authenticates as is denied, pending, revoked or expired.
///
/// Trying again changes none of these, unlike a failure to reach the atServer
/// or to authenticate over a bad link.
enum CredentialRefusal { denied, pending, revoked, expired }

/// The refusal [error] carries, or null when it carries none.
///
/// Read from the atServer's own answer, `error:<code>:<message>`, as it
/// survives in the text of whatever wrapped it: AT0025 denied, AT0026
/// pending, AT0027 revoked, AT0028 expired. The colon after the code is the
/// verb handler's form; an exception the atServer throws, such as a throttle
/// limit, which shares AT0028, travels as `error:AT0028-` or as JSON and is
/// not a refusal.
CredentialRefusal? credentialRefusalIn(Object error) {
  final match = _answer.firstMatch('$error');
  if (match == null) return null;
  return switch (match.group(1)) {
    '25' => CredentialRefusal.denied,
    '26' => CredentialRefusal.pending,
    '27' => CredentialRefusal.revoked,
    _ => CredentialRefusal.expired,
  };
}

final RegExp _answer = RegExp(r'error:AT00(25|26|27|28):');

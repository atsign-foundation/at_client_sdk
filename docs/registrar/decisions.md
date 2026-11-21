# Registrar admin service decisions

## 2026-11-16: `superApiKey` getter, CHANGELOG placement and issue links (#2469)

Context: #2469 "feat(at_auth): register Atsigns with the super API key on
RegistrarAdminService" made `RegistrarAdminService.superApiKey` throw
`UnsupportedError`. Both reviewers (14 Nov) asked for the 4.0.0 behaviour back:
anything that can read the getter already holds the service, and so the key, so
throwing protects nothing and breaks 4.0.0 callers in a minor release. Trunk
has since renamed the unreleased at_auth heading to `4.1.0-rc.1`. That version
is not on pub.dev.

Decision (human):
- `superApiKey` returns the key again, marked `@Deprecated`, with removal
  planned for at_auth 5.0.0.
- The registrar entries go under `## 4.1.0-rc.1` after trunk's entries. The
  pubspec version stays `4.1.0-rc.1`.
- The refinery opens the `at_registrar.dart` issue and the shared registrar
  helper issue on GitHub and links both from the PR.
- These are fix-ups on #2469, not a new PR.

Consequences:
- No runtime break for 4.0.0 callers. The deprecation warning steers them off
  the getter before 5.0.0.
- The CHANGELOG's `deprecated:` entry describes a deprecation, not a throwing
  getter.

## 2026-11-17: the registrar library and the 4.0.0 exports (#2469)

Context: at_auth 4.0.0, as published on pub.dev, exports
`src/registrar/registrar_admin_service.dart` from `at_auth.dart`. #2469 added
a fourth registrar export, `src/registrar/registrar_exceptions.dart`, which
the A3 ratchet refuses (`docs/architecture/invariants.md`: 3 registrar
libraries exported from `at_auth.dart`). The fix moved `RegistrarAdminService`
out to a new `at_auth_registrar_admin.dart`, so a 4.0.0 caller importing only
`at_auth.dart` stops compiling on 4.1.0. #2517 plans a
`package:at_auth/at_registrar.dart` library for every registrar class.

Decision (human):
- `package:at_auth/at_registrar.dart` replaces `at_auth_registrar_admin.dart`.
  It exports `RegistrarAdminService` and `RegistrarException` /
  `RegistrarFailure`.
- `at_auth.dart` keeps exactly its 4.0.0 registrar exports: `registrar.dart`,
  `registrar_service.dart` and `registrar_admin_service.dart`. It does not
  export `registrar_exceptions.dart`. The A3 ratchet stays at 3.
- `RegistrarAdminService` leaves `at_auth.dart` only in at_auth 5.0.0, as part
  of #2517.

Consequences:
- No 4.0.0 caller breaks in 4.1.0.
- Catching `RegistrarException` by type needs `at_registrar.dart`. Code that
  imports only `at_auth.dart` can catch it as `AtException`.
- #2517's question of whether the admin service folds into `at_registrar.dart`
  or stays separate is settled: it folds in.

## 2026-11-17: constructor validation of the port and the super API key (#2469)

Context: a review of #2469 at its current head found that a `registrarUrl`
port of 20 or more digits passes the digits-only pattern, then `int.parse`
overflows and throws `FormatException` instead of the documented
`ArgumentError`. A super API key holding CR/LF or another control character
fails only when the `Authorization` header is set, and is reported as
`RegistrarFailure.network`, which tells the caller the registration may have
been committed. The timeout tests also pass if the send and the body read get
separate `requestTimeout` budgets.

Decision (human):
- A port longer than 5 digits, or one that does not parse, is refused with
  `ArgumentError` named `registrarUrl`, without echoing the value.
- The constructor refuses a super API key that contains a control character
  with `ArgumentError` named `superApiKey`, without echoing the key. The key
  is not trimmed or otherwise repaired.
- A test pins that `requestTimeout` bounds the send and the body read
  together.
- These are fix-ups on #2469, not a new PR.

Consequences:
- A misconfigured service fails at construction, before anything is sent, and
  never as a `network` failure.
- A key read from a file with a trailing newline is refused; the caller trims
  it explicitly.

## 2026-11-17: final validation, cancellation and test rules for #2469

Context: each review round on #2469 found another guard that no test pinned,
because each fix-up covered only the findings listed. Open at the time: a super
API key with a non-ASCII character still fails late and is reported as
`RegistrarFailure.network`; two port guards each mask the other; the `?? []`
defaults for missing delete-flow lists are untested; a cancellation that never
completes holds up the timeout and size-cap failures; `registrarUrl` refuses
hosts with `_`, IPv6 literals and IDN hosts that 4.0.0 accepted, and the key
rule refuses keys with spaces that 4.0.0 sent.

Decision (human):
- Everything that worked in at_auth 4.0.0 keeps working. The constructor
  refuses only input that 4.0.0 could never have used, which 4.0.0 reported
  late or as the wrong error. The deliberate exceptions are user info in
  `registrarUrl` and a tab or DEL in the super API key.
- `registrarUrl` is accepted when `Uri.https(registrarUrl, path)` accepts it,
  as 4.0.0 did, so hosts with `_`, IPv6 literals and IDN hosts keep working.
  It is refused with `ArgumentError` named `registrarUrl`, without echoing the
  value, when `Uri.https` rejects it, when it names no host or one of only
  whitespace and dots, when it carries user info, or when its port is
  outside 1 to 65535.
- The super API key may contain 0x20 to 0x7E, visible ASCII and the space.
  Anything else is refused with `ArgumentError` named `superApiKey`, without
  echoing the key, including a tab or DEL, which dart:io sends in a header
  value and so 4.0.0 sent. This replaces the control-character
  rule above. An empty or whitespace-only key still throws `AtException`, as
  in 4.0.0.
- A delete-flow response that omits `atSigns`, `skippedatSigns`, `deleted` or
  `failed` yields an empty list, as in 4.0.0.
- On a timeout or the size cap the call throws its failure at once;
  cancelling the body stream runs unawaited.
- Every guard in `RegistrarAdminService` is pinned: deleting or altering it
  makes a test fail. A guard that cannot be pinned is removed.
- These are fix-ups on #2469, not a new PR.

Consequences:
- A misconfigured key or URL fails at construction, never as `network`.
- A hung `onCancel` cannot hang a registrar call.
- The 4.0.0 inputs refused that could have worked are a `registrarUrl` with
  user info and a super API key holding a tab or DEL; the CHANGELOG records
  both.

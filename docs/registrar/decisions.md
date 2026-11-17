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

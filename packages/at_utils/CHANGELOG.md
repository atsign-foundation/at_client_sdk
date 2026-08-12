## 3.5.0

- feat: `package:at_utils/at_logger.dart` no longer reaches `dart:io`, so it is
  safe to import from a web/WASM build graph. `at_chops`, `at_auth`, `at_lookup`
  and `at_client` all import this barrel, and it was the path by which `dart:io`
  reached every one of them.

  `src/logging/handlers.dart` keeps the platform-neutral half — the
  `LoggingHandler` interface and `ConsoleLoggingHandler`, the default — and the
  three handlers that need `dart:io` (`FileLoggingHandler`,
  `StdErrLoggingHandler`, `CLILoggingHandler`) move to a new
  `src/logging/handlers_io.dart`, paired with console-backed stand-ins in
  `src/logging/handlers_stub.dart`. `at_logger.dart` selects between them with an
  `if (dart.library.io)` conditional export.

  **This is not a breaking change.** All three handler names are still exported
  from `at_logger.dart` on every platform, with the same constructors, and
  `AtSignLogger.stdErrLoggingHandler` keeps its type — so existing call sites
  compile untouched. On native, behaviour is byte-identical: the handlers are the
  same code, and the pipe-delimited format (including its trailing `" \n"`) is now
  produced by a shared `logRecordLine` helper so the two platforms cannot drift.

  On web, where there is no file system and no stderr, all three route to the
  console and warn once on first use naming what was unavailable. Redirecting
  rather than throwing is deliberate — a logging call should not be what takes an
  application down — but it does mean a web build gets console output where a
  native build writes a file, which is what the warning exists to surface.
- feat: add `logRecordLine(LogRecord)` and `cliLevelLabel(Level)` to
  `at_logger.dart`: the shared log-line format and the CLI level labels
  (`WARN`/`ERROR`/`INFO`/`FINER`), extracted so the `dart:io` handlers and their
  web stubs share one definition.
- test: add `test/logging_handlers_test.dart`, pinning the contract the
  conditional export relies on — every handler name resolves from
  `at_logger.dart`, each satisfies `LoggingHandler`, the `AtSignLogger` statics
  stay assignable to `defaultLoggingHandler`, and the shared format helpers
  behave as specified.
- **Not** addressed: `at_utils.dart` still exports `src/config/app_config.dart`
  (`File`) and `src/networking/pseudo_server_socket.dart` (`ServerSocket`), so
  that barrel remains `dart:io`-bound. Both are reachable only through it and
  neither is ever called on the web; `PseudoServerSocket implements ServerSocket`
  so it cannot be stubbed, only relocated, and at_server consumes both through
  the full barrel. Splitting them is a breaking change for a later major.

## 3.4.0
- feat: Introduce CLILoggingHandler for command-line applications
- fix: made AtSignLogger.level setter case-insensitive
## 3.3.0
- chore(deps): at_commons ^5.5.0
- chore(deps): chalkdart ">=2.0.9<4.0.0"
## 3.2.0
- feat: add ProgressPublisher interface
## 3.1.0
- feat: Add PseudoServerSocket as a generic helper for ALPN
## 3.0.19
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.0
## 3.0.18
- chore: Upgrade at_commons to 4.1.1
## 3.0.17
- chore: Upgrade at_commons to 4.1.0
## 3.0.16
- fix: Uptake at_commons 4.0.0
## 3.0.15
- fix: Replace "LoggingType" with "LoggingHandler" in "AtSignLogger" constructor to enable custom logging
## 3.0.14
- chore: Moved this package to a new repo & updated repository URL
## 3.0.13
- feat: Introduce StdErr(Standard Error) logging type which writes log output to standard error stream
## 3.0.12
- Deprecate formatAtSign() in atsign_util and moved the functionality to fixAtSign()
- Upgrade dependency at_commons to latest version v3.0.42
## 3.0.11
- Change the ConsoleLoggingHandler to static reference
- Update the at_commons version to 3.0.25
## 3.0.10
- at_commons version change to 3.0.17 for AtException hierarchy and introducing new AtException subclasses
## 3.0.9
- Changed at_commons dependency from 3.0.11 to ^3.0.11
## 3.0.8
- at_commons version change for renaming NotifyDelete verb to NotifyRemove
## 3.0.7
- at_commons version change for Info and NoOp verb
- at_commons version change for NotifyDelete verb
## 3.0.6
- at_commons version change for AtTimeoutException
## 3.0.5
- Fix formatAtSign bug for null value
## 3.0.4
- at_commons version change for AtKey creation
## 3.0.3
- Changes to reset ttb
## 3.0.2
- at_commons version change for compaction and notification expiry
## 3.0.1
- at_commons version change for AtKey validations
## 3.0.0
- at_commons version change for sync_pagination
## 2.0.4
- at_commons version change for last notification time in monitor
## 2.0.3
- at_commons version change for stream resume
## 2.0.2
- at_commons version change
## 2.0.1
- at_commons version change
## 2.0.0
- Null safety upgrade
## 1.0.1+8
- Minor improvements in atmetadata utils
- at_commons version change
## 1.0.1+7
- Third party package dependency upgrade
## 1.0.1+6
- Replace ByteBuffer with ByteBuilder
## 1.0.1+5
- Notification sub system changes
## 1.0.1+4
- added createdAt and updatedAt to metadata
  Introduced batch verb for sync
## 1.0.1+3
- Metadata util improvements and at_commons version change
## 1.0.1+2
- at_commons version change
## 1.0.1+1
- at_commons version change
## 1.0.1
- Fixed issues reported by dartanalyzer
## 1.0.0
- Initial version, created by Stagehand

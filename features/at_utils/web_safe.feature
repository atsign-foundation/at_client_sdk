Feature: at_utils 4.0.0's default barrels build for the web

  at_utils.dart, at_logger.dart and at_progress.dart reach no dart:io, so a
  program built for the browser can import them. Anything that needs a
  filesystem, stderr or a terminal comes from at_utils_io.dart.

  Races: none arise; the change moves code between libraries and adds no
  state.
  Replay: none arise; nothing here is issued, signed or accepted.
  DoS: none arise; nothing here reads input, and the logging handlers keep
  their behaviour.
  Forgery and impersonation: none arise; nothing here acts for an atSign.

  Scenario: The default barrels reach no platform library
    Given at_utils 4.0.0
    When wasm_shakedown walks at_utils.dart, at_logger.dart and at_progress.dart
    Then none of them reaches dart:io, directly or through another package
    And each compiles with dart2wasm

  Scenario: Native logging comes from the io barrel
    Given a program that imports at_utils_io.dart
    When it logs to stderr, to a file or to a terminal in colour
    Then StdErrLoggingHandler, FileLoggingHandler and CLILoggingHandler do it as they did in at_utils 3

  Scenario: A progress event prints without terminal colour codes
    Given a ProgressEvent
    When it is turned into a string
    Then the string holds its time, type, group and message, and no terminal escape codes

  Scenario: A CLI still colours its progress output
    Given at_onboarding_cli printing the progress of an activation
    When a progress event arrives
    Then its type and group are coloured by type, as before

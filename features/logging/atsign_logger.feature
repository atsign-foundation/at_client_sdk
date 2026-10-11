Feature: AtSignLogger hands its LoggingHandler printable text

  Each record an AtSignLogger hands its LoggingHandler, built-in or custom,
  carries its message and logger name with every control character (C0, DEL,
  C1) written as a visible escape (`\r`, `\x1b`), except that each LF in the
  message is kept and followed by two spaces. Only a record's first line
  starts at the margin, and the only control character a handler is handed is
  that LF.

  Races: none arise; the escape is a function of one record, applied before
  the handler is called.
  Replay: none arises; nothing is issued or checked.
  DoS: an escaped message is at most four times the length of the message
  logged (`\x9b` for one character), so a call site logging text from outside
  the process still bounds its length.

  Background:
    Given an AtSignLogger whose LoggingHandler keeps each record it is handed

  Scenario: A message's control characters other than LF reach the handler as visible escapes
    When it logs at info the message "k", CR, ESC, "[2J", LF, "yy"
    Then the handler is handed the message `k\r\x1b[2J`, LF, two spaces, "yy"

  Scenario: A line in a message cannot start a record
    When it logs at info the message "a", LF, "INFO|x"
    Then the handler is handed the message "a", LF, two spaces, "INFO|x"

  Scenario: A backslash in a message reaches the handler unchanged
    When it logs at info the message `C:\logs\x1b`
    Then the handler is handed the message `C:\logs\x1b`

  Scenario: A message with nothing to escape reaches the handler as the record logged
    When it logs at info the message "hello"
    Then the handler is handed the record the logger made, with its time and sequence number

  Scenario: A stack trace logged as the message reaches the handler with each later line indented
    When it logs at warning, as the message, a stack trace of two frames, whose text ends with LF
    Then the handler is handed the first frame, LF, two spaces, the second frame, LF, two spaces

  Scenario: A logger name's control characters reach the handler as visible escapes
    Given the AtSignLogger is named "sync", LF, "INFO"
    When it logs at info the message "hello"
    Then the handler is handed the logger name `sync\nINFO`

  Scenario: A record's error and stack trace reach the handler unchanged
    When it logs at severe the message "failed" with an error whose text holds LF, and a stack trace
    Then the handler is handed that error object and that stack trace

  Scenario: A listener on the underlying logger is handed the message as logged
    Given a listener on the AtSignLogger's logger.onRecord
    When it logs at info the message "k", CR, "yy"
    Then the listener is handed the message "k", CR, "yy"

  Scenario Outline: A built-in handler writes the escaped message
    Given an AtSignLogger whose LoggingHandler is a <handler>
    When it logs at info the message "k", CR, ESC, "[2J", LF, "yy"
    Then the <handler> writes two lines, the first holding `k\r\x1b[2J` and the second two spaces then "yy"

    Examples:
      | handler               |
      | ConsoleLoggingHandler |
      | StdErrLoggingHandler  |
      | FileLoggingHandler    |
      | CLILoggingHandler     |

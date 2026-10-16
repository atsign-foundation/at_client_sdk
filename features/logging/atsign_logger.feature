# Proposed, awaiting agreement: the scenarios tagged @proposed, and in the
# description the bidirectional formatting characters, the line and paragraph
# separators, the limit to the message and logger name, the copy's time and
# sequence number, the DoS bound of six times, and the Forgery line's
# reordering and splitting.
Feature: AtSignLogger hands its LoggingHandler printable text

  Each record an AtSignLogger hands its LoggingHandler, built-in or custom,
  carries its message and logger name with every control character (C0, DEL,
  C1), every bidirectional formatting character (U+061C, U+200E, U+200F,
  U+202A to U+202E, U+2066 to U+2069) and the line and paragraph separators
  (U+2028, U+2029) written as a visible escape (`\r`, `\x1b`, `\u202e`),
  except that each LF in the message is kept and followed by two spaces. In
  the message and logger name a handler is handed, only the message's first
  line starts at the margin, and the only control character is that LF. A
  record with something to escape is handed over as a copy, which has its
  own time and sequence number.

  Races: none arise; the escape is a function of one record, applied before
  the handler is called.
  Replay: none arises; nothing is issued or checked.
  DoS: an escaped message is at most six times the length of the message
  logged (`\u202e` for one character), so a call site logging text from
  outside the process still bounds its length.
  Forgery: text logged from outside the process cannot start a record of its
  own, move a terminal's cursor, clear its screen, reorder the line with
  bidirectional formatting characters, nor split it with a line or paragraph
  separator, in the message and logger name a handler is handed (the
  scenarios tagged @forgery).
  Impersonation: a message cannot pass as another logger's record, since none
  of its lines can start a record; the name an AtSignLogger is given is its
  creator's choice and outside this feature.

  Background:
    Given an AtSignLogger whose LoggingHandler keeps each record it is handed

  @forgery
  Scenario: A message's control characters other than LF reach the handler as visible escapes
    When it logs at info the message "k", CR, ESC, "[2J", LF, "yy"
    Then the handler is handed the message `k\r\x1b[2J`, LF, two spaces, "yy"

  @forgery
  Scenario: A line in a message cannot start a record
    When it logs at info the message "a", LF, "INFO|x"
    Then the handler is handed the message "a", LF, two spaces, "INFO|x"

  @forgery @proposed
  Scenario: A message's bidirectional formatting characters reach the handler as visible escapes
    When it logs at info the message "a", U+202E, "b", U+2066, "c"
    Then the handler is handed the message `a\u202eb\u2066c`

  @forgery @proposed
  Scenario: A line or paragraph separator in a message cannot start a line
    When it logs at info the message "a", U+2028, "INFO|x", U+2029, "y"
    Then the handler is handed the message `a\u2028INFO|x\u2029y`

  @proposed
  Scenario: An emoji sequence in a message reaches the handler unchanged
    When it logs at info a message holding an emoji joined by U+200D and a flag built from tag characters
    Then the handler is handed that message unchanged

  Scenario: A backslash in a message reaches the handler unchanged
    When it logs at info the message `C:\logs\x1b`
    Then the handler is handed the message `C:\logs\x1b`

  Scenario: A message with nothing to escape reaches the handler as the record logged
    When it logs at info the message "hello"
    Then the handler is handed the record the logger made, with its time and sequence number

  Scenario: A stack trace logged as the message reaches the handler with each later line indented
    When it logs at warning, as the message, a stack trace of two frames, whose text ends with LF
    Then the handler is handed the first frame, LF, two spaces, the second frame, LF, two spaces

  @forgery
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

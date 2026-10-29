Feature: A connection writes a command only when it is one line

  The atServer ends a command at a line feed. A connection refuses to write a
  command holding a line feed anywhere but its last character: write throws
  IllegalArgumentException, naming the line feed's offset and the command's
  length but not the command, before any byte is sent. A carriage return is
  written as given, since only a line feed ends a command.

  Races: the check reads only the command it is handed, before the first byte
  is written, and changes no state the connection or a second caller shares.
  Replay: nothing is issued or checked.
  DoS: one scan of the command for a line feed; a refused command opens
  nothing, and leaves the connection usable for the next command.
  Forgery and impersonation: a write reaches the atServer as one command or
  not at all.

  Scenario: A command holding a line feed before its end is refused, and nothing is sent
    Given a connection to an atServer
    When a command holding a line feed before its last character is written
    Then write throws IllegalArgumentException before any byte reaches the atServer
    And the connection stays usable: the next one-line command is sent as given

  Scenario: A one-line command is sent as given
    Given a connection to an atServer
    When a command whose only line feed is its last character, or one with no line feed, is written
    Then it is sent as given

  Scenario: A carriage return is sent as given
    Given a connection to an atServer
    When a command holding a carriage return, and no line feed before its end, is written
    Then it is sent as given

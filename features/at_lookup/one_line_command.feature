Feature: A connection writes a command only when it is one line

  The atServer ends a command at a line feed. A connection refuses to write a
  command holding a line feed anywhere but its last character: write throws
  IllegalArgumentException, naming the line feed's offset and the command's
  length but not the command, before any byte of it is sent. A lookup refuses
  such a command from executeCommand or executeVerb before it looks up,
  connects to or authenticates with the atServer: executeCommand throws
  IllegalArgumentException, and executeVerb an AtLookUpException with code
  AT0022. A carriage return is written as given, since only a line feed ends a
  command.

  Races: the check reads only the command it is handed, before the lookup
  takes its request mutex or the first byte is written, and changes no state
  the connection or a second caller shares.
  Replay: nothing is issued or checked.
  DoS: one scan of the command for a line feed. A command refused by
  executeCommand or executeVerb opens no connection and authenticates
  nothing; one refused by a write is written nowhere, and the connection
  stays usable for the next command.
  Forgery and impersonation: no write carries a line feed before its end.

  Scenario: A command holding a line feed before its end is refused, and none of it is sent
    Given a connection to an atServer
    When a command holding a line feed before its last character is written
    Then write throws IllegalArgumentException before any byte of it reaches the atServer
    And the connection stays usable: the next one-line command is sent as given

  Scenario: A lookup refuses such a command before it connects or authenticates
    Given a lookup with no connection up
    When a command holding a line feed before its last character, and needing authentication, is run through executeCommand or executeVerb
    Then executeCommand throws IllegalArgumentException, and executeVerb an AtLookUpException with code AT0022
    And the lookup has looked up no atServer, opened no connection and authenticated nothing

  Scenario: A one-line command is sent as given
    Given a connection to an atServer
    When a command whose only line feed is its last character, or one with no line feed, is written
    Then it is sent as given

  Scenario: A carriage return is sent as given
    Given a connection to an atServer
    When a command holding a carriage return, and no line feed before its end, is written
    Then it is sent as given

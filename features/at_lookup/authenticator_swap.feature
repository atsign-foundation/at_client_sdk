Feature: A login serves only the authenticator that made it

  A lookup's authenticator decides who its connection logs in as. When the
  caller installs another one, the next authentication, or the next command
  that needs authentication, closes a connection logged in by the old one and
  logs in on a new connection with the new one.

  Races: a command already running on the old login is ended by the close,
  and an authentication and a command waiting behind it share the one new
  login.
  Replay: the new login answers a new challenge on its own connection.
  DoS: one new connection per change of authenticator; a login made by the
  installed authenticator is reused, never repeated.
  Forgery and impersonation: no command runs as an enrollment the installed
  authenticator does not log in as, and with no authenticator installed a
  command that needs authentication fails rather than using the old login.

  Scenario: An authenticator installed over a login logs in for itself
    Given a lookup whose connection the authenticator for one enrollment logged in
    When the caller installs the authenticator for another enrollment and the lookup authenticates
    Then the new authenticator runs on a new connection, and the connection records the other enrollment

  Scenario: A command after a change of authenticator runs on the new login
    Given a lookup whose connection the authenticator for one enrollment logged in
    When the caller installs the authenticator for another enrollment and runs a command that needs authentication
    Then the new authenticator logs in on a new connection before the command, which runs there

  Scenario: The authenticator that made a login keeps using it
    Given a lookup whose connection its authenticator logged in
    When the lookup authenticates again, and runs a command that needs authentication
    Then the authenticator does not run again and nothing opens a new connection

  Scenario: A command with no authenticator does not use the old login
    Given a lookup whose connection its authenticator logged in
    When the caller removes the authenticator and runs a command that needs authentication
    Then the command fails with UnAuthenticatedException and nothing is sent

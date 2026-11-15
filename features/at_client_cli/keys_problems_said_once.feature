Feature: A CLI program says what is wrong with the keys once, and what to do next

  at_activate and every program built on CLIBase report a keys problem in
  one message on stderr: what is wrong, where they looked, and the next
  command. When the keys are absent, at_activate looks up whether the atSign
  has a public key, as at_activate status does, to give the one hint that
  applies. Every keys problem ends with one footer line. Network failures
  keep their own wording.

  Races: none arise; the lookup reads one public value once.
  Replay: none arise; the lookup is unauthenticated and nothing is signed.
  DoS: one lookup, on an error path only.
  Forgery: a spoofed atDirectory or atServer can change only the hint,
  never an authentication decision.
  Impersonation: none arise; no credential is used or sent.

  Background:
    Given the footer "Need help? support@atsign.com. Never send anyone your .atKeys file, support included."

  Scenario Outline: No keys and the atSign not yet activated
    Given no keyfile for @alice at <path>, and @alice's atServer holds no public key for @alice
    When the user runs "at_activate <command> -a @alice"
    Then stderr holds, once, "No keys for @alice at <path>." then "@alice has not been activated yet. To activate it: at_activate onboard -a @alice" then the footer, and it exits 1
    Examples:
      | command |
      | otp     |
      | list    |
      | approve |

  Scenario: No keys and the atSign activated elsewhere
    Given no keyfile for @alice at <path>, and @alice's atServer holds a public key for @alice
    When the user runs "at_activate otp -a @alice"
    Then stderr holds, once, "No keys for @alice at <path>." then "@alice is activated, but not on this machine. Run this command on the machine that activated it, or enroll this machine first." then the footer, and it exits 1

  Scenario: No keys and the atSign not in the atDirectory
    Given no keyfile for @alice at <path>, and an atDirectory with no entry for @alice at <root>
    When the user runs "at_activate otp -a @alice"
    Then stderr holds, once, "No keys for @alice at <path>." then "@alice is not in the atDirectory at <root>. Check the spelling, or -r." then the footer, and it exits 1

  Scenario: No keys and the atDirectory unreachable
    Given no keyfile for @alice at <path>, and an atDirectory that cannot be reached
    When the user runs "at_activate otp -a @alice"
    Then stderr holds, once, "No keys for @alice at <path>." then "  Not activated yet?             at_activate onboard -a @alice" then "  Activated on another machine?  Run this command there, or enroll this machine first." then the footer, and it exits 1

  Scenario: A passphrase-protected keyfile without its passphrase
    Given a passphrase-protected keyfile for @alice at <path>
    When the user runs "at_activate otp -a @alice" without -P
    Then stderr holds, once, "Could not read the keys for @alice at <path>: the passphrase is wrong or missing." then "  If the keyfile has a passphrase, pass it with -P." then the footer, and it exits 1

  Scenario: A keyfile for another atSign
    Given a keyfile at <path> whose atsign is @bob
    When the user runs "at_activate otp -a @alice -k <path>"
    Then stderr holds, once, "The keys at <path> are for @bob, not @alice. Check -a and -k." then the footer, and it exits 1

  Scenario: Keys with no authentication keypair this machine can use
    Given a keyfile for @alice at <path> that holds no authentication keypair for the enrollment it authenticates as
    When the user runs "at_activate otp -a @alice"
    Then stderr holds, once, the message open throws for those keys, then the footer, and it exits 1

  Scenario: A keyfile holding only a pending enrollment request
    Given a keyfile for @alice at <path> that holds only a pending enrollment request, id e-1
    When the user runs "at_activate otp -a @alice"
    Then stderr holds, once, "The keyfile at <path> holds only a pending enrollment request for @alice (id e-1). Once it is approved, run the same at_activate enroll command again to finish it." then the footer, and it exits 1

  Scenario: A keyfile left with no credential
    Given a keyfile for @alice at <path> that holds no credential and no pending request
    When the user runs "at_activate otp -a @alice"
    Then stderr holds, once, the no-credential line then the footer, and it exits 1

  Scenario: A keys problem is said once, with no prefix, retry advice or stack trace
    Given no keyfile for @alice at <path>
    When the user runs "at_activate otp -a @alice"
    Then no line of stderr appears twice, and stderr holds no "ERROR: otp : Exception:", no "Please try again" and no stack trace

  Scenario: A program built on CLIBase says the same
    Given no keyfile for @alice at <path>
    When a program calls CLIBase.fromCommandLineArgs for @alice
    Then it writes "No keys for @alice at <path>." once on stderr and throws AtKeysUnusableException with cause absent

  Scenario: A network failure still says to try again
    Given a readable keyfile for @alice and an atServer that cannot be reached
    When the user runs "at_activate otp -a @alice"
    Then stderr says it failed to connect and to try again, as before, without the keys footer

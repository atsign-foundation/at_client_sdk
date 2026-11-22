Feature: at_activate cancel removes the request its keyfile is waiting on

  at_activate cancel, given the keyfile an at_activate enroll command used,
  removes that keyfile's one pending enrollment request, whatever app and
  device it was filed under, and sends nothing. The request stays on the
  atServer, for the Atsign's manager to deny, or to revoke if they approved
  it meanwhile, and cancel says so. It refuses a keyfile holding live keys,
  and says when there is nothing to cancel. Afterwards at_activate enroll
  with that keyfile files a new request.

  Races: cancel and an approval being filed by another process on this
  device take the keyfile's lock in turn. If the approval is filed first,
  cancel finds live keys and refuses; if cancel is first, that process's
  wait files nothing when the approval lands and says the manager can revoke
  it.
  Replay: none arises; cancel sends nothing.
  DoS: none arises; cancel reads and writes one local keyfile.
  Forgery and impersonation: cancel acts only on the keyfile it is given,
  which only programs on this device write, and removes only pending
  material, never keys that were ever live.

  Scenario: cancel removes the keyfile's pending request and says the manager can deny it
    Given a keyfile holding a pending enrollment <id> for @alice, filed by app "buzz" on device "phone"
    When at_activate cancel runs for @alice on that keyfile
    Then the keyfile holds no pending request, nothing is sent, it says "Enrollment <id> of @alice is cancelled" and that the manager of @alice can deny it, or revoke it if they approved it already, and it exits 0

  Scenario: enroll files a new request on a keyfile cancel emptied
    Given a keyfile from which at_activate cancel removed @alice's pending request
    When at_activate enroll runs for @alice on that keyfile
    Then it submits a new enrollment request and files it in that keyfile

  Scenario: cancel refuses a keyfile holding live keys
    Given a keyfile holding live keys for @alice
    When at_activate cancel runs for @alice on that keyfile
    Then the keyfile is unchanged, it says the keyfile holds live keys, which cancel never removes, and that the manager of @alice can revoke this device's enrollment, and it exits 1

  Scenario Outline: cancel says when there is nothing to cancel
    Given <keyfile> for @alice
    When at_activate cancel runs for @alice on that keyfile
    Then nothing changes, nothing is sent, it says @alice has no pending request in that keyfile, and it exits 1

    Examples:
      | keyfile                                     |
      | a keyfile holding no request and no keys    |
      | no keyfile at the path given                |

  Scenario: cancel needs the keyfile, as enroll does
    When at_activate cancel runs for @alice without -k
    Then it says the -k option is mandatory for the cancel command, and it exits 1

  Scenario: a CLIBase program waiting on a pending request names at_activate cancel
    Given a CLIBase program started for @alice on a keyfile holding a pending enrollment <id>
    When it waits for the approval
    Then it says it is waiting for approval of enrollment <id> of @alice, and that at_activate cancel -a @alice -k <keyfile> gives the request up

  Scenario: at_activate's report of a keyfile waiting on a request names at_activate cancel
    Given a keyfile holding only a pending enrollment <id> for @alice
    When an at_activate command that needs live keys runs for @alice on that keyfile
    Then its report says to run the same at_activate enroll command again once the request is approved, or at_activate cancel to give it up

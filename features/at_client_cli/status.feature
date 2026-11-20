Feature: at_activate status says whether an Atsign's public key can be looked up

  Races: one read of public values; nothing shared changes.
  Replay: nothing is signed or sent that could be replayed.
  DoS: one lookup per run, bounded by the finder's deadline.
  Forgery: a spoofed atDirectory or atServer changes only the reported code, which they already control.
  Impersonation: no credential is held or used; the operator names the Atsign.

  Scenario Outline: at_activate status returns <code> when <case>
    Given <setup>
    When at_activate status -a @alice runs with its root on the loopback interface
    Then it returns <code>
    Examples:
      | case                    | setup                                                            | code |
      | found                   | an atDirectory naming an atServer that holds @alice's public key | 0    |
      | absent                  | that atServer holds no public key for @alice                     | 1    |
      | atServer unreachable    | the atDirectory names an atServer nothing answers                | 2    |
      | not in the atDirectory  | the atDirectory has no record for @alice                         | 3    |
      | atDirectory unreachable | nothing answers at the root                                      | 4    |

  Scenario: at_activate status closes its connection to the atServer
    Given an atDirectory naming an atServer that holds @alice's public key
    When at_activate status -a @alice runs
    Then it returns 0, and its connection to the atServer is closed

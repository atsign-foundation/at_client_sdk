Feature: A refused PKAM is read by the client's one classifier
  The passkey gateway decides whether the atServer refused an enrollment's
  PKAM with classifyConnectionFailure, the classifier every client open
  uses. Denied, revoked, an enrollment the atServer calls expired or
  invalid, and a signature that did not verify are refusals, which end the
  device's hints for that passkey. A pending enrollment, a lost connection
  or a server error is not.

  Forgery and impersonation: the reply is the atServer's own answer on the
  connection that sent the `pkam:`, and atServers are trusted as faithful.
  Denial of service: a failure that is not a refusal keeps the device's
  hints, so a transient failure costs no second prompt. Races and replay:
  nothing here is stored or resent.

  Scenario Outline: A PKAM the atServer refuses for the passkey's enrollment is a lost passkey
    Given the atServer refuses the passkey enrollment's PKAM with <code> because <reason>
    When the app logs in to @alice🛠 on a device that remembers nothing for it
    Then it throws a PasskeyLostException whose cause is a PkamRefusedException

    Examples:
      | code   | reason                                                    |
      | AT0401 | the signature did not verify                              |
      | AT0025 | the enrollment is denied                                  |
      | AT0027 | the enrollment is revoked                                 |
      | AT0028 | the enrollment, named in the reply, is expired or invalid |

  Scenario Outline: A PKAM failure that is not a refusal propagates as it is
    Given the atServer <failure> for the passkey enrollment's PKAM
    When the app logs in to @alice🛠 with that passkey
    Then that failure propagates as it is
    And the device's passkey hints are kept

    Examples:
      | failure                                          |
      | answers AT0026 because the enrollment is pending |
      | answers with a server error                      |
      | closes the connection                            |

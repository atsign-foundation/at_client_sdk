Feature: A refused PKAM is read by the client's one classifier
  The passkey gateway decides whether the atServer refused an enrollment's
  PKAM with classifyConnectionFailure, the classifier every client open
  uses, which reads a code written in the dash, colon or JSON form. Only a
  reply to the pkam: can be a refusal. Denied, revoked, an enrollment the
  atServer calls expired or no longer holds (AT0028 or AT0029, whether or
  not the reply names the enrollment), a signature that did not verify, and
  a reply that carries no code are refusals: a login with no saved hints
  reports a lost passkey, and one with saved hints tries once more without
  them. A pending enrollment, a lost connection or a server error is not.
  A failure at the from: on the PKAM's connection, before any pkam: is
  sent, is never a refusal, whatever its code, since no key was tested. An
  at_client connection reads an error reply to its from: by its code and
  reports a connection state that the next open clears; the gateway reads
  it differently on purpose, because its refusal ends in a lost passkey.
  Every from: the gateway sends to authenticate names at_client as the SDK,
  with its version, as every other from: at_client sends does.

  Forgery and impersonation: a reply to the pkam: comes from the atServer
  that tested the key, so it can say the key or the enrollment was refused.
  A reply to the from: can come from a server that does not host the
  Atsign, such as one at a stale address, so it says nothing about the key.
  Whoever answers at the address could instead issue a challenge and refuse
  the pkam:, which is a refusal either way, so not reading the from: reply
  as one denies nobody anything they had. The clientConfig a from: carries
  is the client's own claim: an atServer reads its version to choose the
  form of its error replies, and it grants the client nothing. Denial of
  service: a failure that is not a refusal keeps the device's hints, so a
  failure that whoever answers at the address can cause at will costs no
  second prompt and offers no Reset. Races: whether the pkam: was sent is
  recorded for one attempt, and an attempt the connection makes again
  starts afresh. Replay: nothing here is stored or resent.

  Scenario Outline: A PKAM the atServer refuses for the passkey's enrollment is a lost passkey
    Given the atServer refuses the passkey enrollment's PKAM with <code> because <reason>
    When the app logs in to @alice🛠 on a device that remembers nothing for it
    Then it throws a PasskeyLostException whose cause is a PkamRefusedException

    Examples:
      | code    | reason                                                         |
      | AT0401  | the signature did not verify                                   |
      | AT0025  | the enrollment is denied                                       |
      | AT0027  | the enrollment is revoked                                      |
      | AT0028  | the enrollment has expired, or the atServer no longer holds it |
      | AT0028  | the enrollment has expired, though the reply does not name it  |
      | AT0029  | the enrollment has expired, or the atServer no longer holds it |
      | no code | the reply is a bare prompt                                     |
      | no code | the reply carries no error:                                    |

  Scenario Outline: A refusal reads the same in every form the atServer writes it in
    Given the atServer refuses the passkey enrollment's PKAM with AT0401 in the <form> form
    When the app logs in to @alice🛠 on a device that remembers nothing for it
    Then it throws a PasskeyLostException whose cause is a PkamRefusedException

    Examples:
      | form  |
      | dash  |
      | colon |
      | JSON  |

  Scenario Outline: A failure at the from: on the PKAM's connection is not a refusal
    Given the atServer answers the from: on the passkey enrollment's PKAM connection with <answer>
    When the app logs in to @alice🛠 on a device that remembers nothing for it
    Then that failure propagates as it is, and no pkam: is sent

    Examples:
      | answer                         |
      | error:AT0401 in the dash form  |
      | error:AT0401 in the colon form |
      | error:AT0401 in the JSON form  |
      | data: and nothing else         |

  Scenario: A failure at the from: keeps a device's passkey hints
    Given a device that remembers @alice🛠's passkey and enrollment
    And the atServer answers the from: on the passkey enrollment's PKAM connection with error:AT0401
    When the app logs in to @alice🛠
    Then that failure propagates as it is, the passkey is asked for once, and the device's passkey hints are kept

  @race
  Scenario: A PKAM attempt the connection makes again starts afresh, so a failure at its from: is not a refusal
    Given the passkey enrollment's first PKAM attempt sent its pkam:, and the connection was lost before the reply
    And the atServer answers the from: of the attempt the connection makes again with error:AT0401
    When the app logs in to @alice🛠 on a device that remembers nothing for it
    Then that failure propagates as it is

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

  Scenario Outline: The from: on the passkey's PKAM connection names at_client as the SDK
    Given an app that sets no client particulars, which no passkey entry point takes
    When the passkey gateway authenticates the passkey's enrollment <when>
    Then the from: it sends carries at_client's clientConfig: at_client as the SDK, at_client's version as the sdk version and as version

    Examples:
      | when                                    |
      | at a login                              |
      | when an onboarding activates the Atsign |

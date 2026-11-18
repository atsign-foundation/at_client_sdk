Feature: An atServer that gives no challenge to sign leaves the connection offline, not refused

  A client authenticates by signing the challenge its atServer answers from:
  with. An answer that carries no challenge the client will sign says nothing
  about the client's keys: no answer, data: with nothing, a bare prompt, a
  malformed challenge, or a challenge issued for another atSign. at_client
  still signs none of them, and reports the connection offline with cause
  unreachable, as it does a reply it cannot read: a first open hands back its
  client, and the error reaches the caller as it is. An error: reply to from:
  is read by its code, as pkam_server_error.feature reads a pkam: reply, and
  a pkam: reply that carries no code is still a refusal.

  Races: none arise; each answer is read on the connection it arrived on.
  Replay: the client still signs only a challenge issued to its own atSign;
  only the state it reports changes.
  DoS: an atServer that gives no challenge can now be retried where a refusal
  was not, by the app's own awaitOnline within its budget and by the verbs
  the client sends anyway; no retry is added.
  Forgery and impersonation: the client signs nothing it did not sign before,
  and still refuses a challenge issued for another atSign. Its keys were never
  tested, so reporting the connection unreachable rather than refused claims
  nothing about them.

  Scenario Outline: A from: answer with no challenge to sign leaves the connection offline
    Given a client of an approved enrollment of @alice🛠
    When the atServer answers its connection's from: with <answer>
    Then the client signs nothing, and the connection state is offline with cause unreachable, carrying the error

    Examples:
      | answer                          |
      | nothing                         |
      | data: and nothing else          |
      | a bare @alice🛠@ prompt         |
      | a malformed challenge           |
      | a challenge issued for @bob🛠   |

  Scenario: A first open whose from: gets no challenge hands back its client
    Given a device where @alice🛠's keys have never been online
    When the app opens @alice🛠 and the atServer answers from: with data: and nothing else
    Then open hands back a client whose connection state is offline with cause unreachable

  Scenario: Checking which enrollment keys authenticate as throws a missing challenge as it is
    Given keys for an enrollment of @alice🛠
    When the app calls authenticatesAs and the atServer answers from: with data: and nothing else
    Then that error propagates as it is, and no AtCredentialRefusedException is thrown

  Scenario: A verb whose from: gets no challenge reports the connection offline
    Given a client of @alice🛠 whose connection state is online
    When a verb's from: on a new connection is answered with data: and nothing else
    Then the verb throws, and the connection state is offline with cause unreachable

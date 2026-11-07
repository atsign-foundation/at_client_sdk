Feature: An application envelope verifies offline against a published _apsk

  verifySignedEnvelope, which is experimental, checks a SignedEnvelope
  against a PublishedApsk: an Atsign, one of its enrollment ids, and the
  _apsk value that enrollment published at public:_apsk.<id>.a.__e@<atSign>,
  read by a plain lookup, by fetchPublishedApsk, or held from earlier. It
  needs no AtClient, network or clock, and never throws. It returns
  EnvelopeVerified, naming the kid, algorithm and key status that verified
  and whether the signature confirms the signer's Atsign, or
  EnvelopeRefused, naming an EnvelopeRefusal, a one-line reason and the kid
  whenever one is known. It verifies application envelopes (typ
  at-app+jws) only. An envelope whose iss names another Atsign than the
  PublishedApsk's is refused; one that names no Atsign, as at_client 4.0.0
  signed them, verifies with issuerConfirmed false. An envelope whose enid
  is absent or names another enrollment is refused. By default the
  strongest algorithm the envelope and the _apsk share is accepted;
  minimumAlgorithm refuses anything weaker.

  selectEnvelopeKey makes every check verifySignedEnvelope makes except the
  signature, without reading the payload, and returns the kid and key
  status verifySignedEnvelope would use, or the same refusal; the two share
  one selection. SignedEnvelope.parse refuses text over a length in UTF-8
  bytes the caller names before decoding it, and an _apsk value over
  maxPublishedApskLength is refused before it is read. Every name a caller
  needs reaches it through at_client.dart, and so through at_client_cli and
  at_client_flutter. TestEnvelopeSigner, from the test-support library,
  signs offline for an Atsign, enrollment and algorithm and gives the
  PublishedApsk that verifies it.

  Races: verifySignedEnvelope and selectEnvelopeKey hold no state, cache,
  clock or I/O, and SignedEnvelope and PublishedApsk are immutable, so
  concurrent calls are independent. A result describes the _apsk value it
  was given, which the owner may have rotated or revoked since it was
  read; the result carries no time.
  Replay: a result attests who signed, not when or for whom. The protected
  header carries no time, nonce or audience, so an envelope verifies each
  time it is presented while the _apsk lists its key; telling repeats apart
  is the caller's.
  DoS: envelope text is bounded by the caller before it is decoded, the
  _apsk value is bounded before it is read, and a call makes at most one
  public-key operation; selectEnvelopeKey makes none. The type, version,
  Atsign, enrollment and algorithm are checked before any.
  Forgery and impersonation: the payload and protected header are verified
  as received, and the type, version, Atsign, enrollment and kid are inside
  the signature. issuerConfirmed is true only when the signature covers an
  iss naming the PublishedApsk's Atsign. The result rests on the _apsk value
  the caller supplies; a value read from an Atsign's atServer rests on that
  atServer for the keys it lists.

  Background:
    Given @alice's enrollment E publishes an _apsk listing one active ML-DSA-65 client data signing key K
    And a client of E on this release made an envelope with wrapAndSign over a JSON result

  Scenario Outline: A program that imports only its platform package signs and verifies an envelope
    Given a program whose only SDK import is <library>, holding an AtClient for E
    When it signs a payload with AtClientEnvelopeSigner.wrapAndSign, fetches E's PublishedApsk with fetchPublishedApsk, and checks the envelope with verifySignedEnvelope
    Then the result is EnvelopeVerified, and SignedEnvelope, PublishedApsk, EnvelopeVerification, EnvelopeVerified, EnvelopeRefused, EnvelopeRefusal, EnvelopeKeySelection, EnvelopeKeySelected, ApskSigningKey, KeyEntryStatus, SigningAlgoType, Atsign and AtSigningVerificationException all resolve from that one import

    Examples:
      | library                                          |
      | package:at_client_cli/at_client_cli.dart         |
      | package:at_client_flutter/at_client_flutter.dart |

  Scenario: A valid envelope verifies against its signer's published _apsk
    Given a verifier holding the envelope and the value of public:_apsk.E.a.__e@alice, and no AtClient
    When it calls verifySignedEnvelope with PublishedApsk(atSign: "@alice", enrollmentId: E, value: that value)
    Then the result is EnvelopeVerified naming @alice, E, kid K, mldsa65, key status active and issuerConfirmed true

  Scenario: fetchPublishedApsk returns the _apsk an enrollment published, with whose it is
    Given a client of @bob
    When it calls fetchPublishedApsk("@alice", E)
    Then it returns a PublishedApsk whose atSign is "@alice", whose enrollmentId is E and whose value is the value of public:_apsk.E.a.__e@alice

  @race
  Scenario: fetchPublishedApsk refuses an enrollment the atServer has revoked
    Given @alice revoked E, so the atServer moved E's _apsk to public:_apsk.E.r.__e@alice
    When a client of @bob calls fetchPublishedApsk("@alice", E)
    Then it throws WithdrawnSigningKeyException with location r.__e

  @forgery
  Scenario: A payload changed by one byte does not verify
    Given the envelope with one character of its payload changed
    When the verifier checks it against E's _apsk
    Then the result is EnvelopeRefused with badSignature, naming kid K

  @forgery @impersonation
  Scenario: An envelope is refused against the _apsk of an Atsign it does not name
    Given @bob's enrollment F publishes an _apsk listing its own key
    When the verifier checks the envelope against PublishedApsk(atSign: "@bob", enrollmentId: F, value: F's _apsk)
    Then the result is EnvelopeRefused with wrongAtSign, naming "@alice", "@bob" and kid K

  @forgery @impersonation
  Scenario: An envelope that names no Atsign verifies, and says the signature does not confirm the Atsign
    Given an envelope a client of E signed with at_client 4.0.0, naming enid E and no iss
    When the verifier checks it against PublishedApsk(atSign: "@alice", enrollmentId: E, value: E's _apsk)
    Then the result is EnvelopeVerified naming kid K with issuerConfirmed false

  @impersonation
  Scenario: An envelope is refused against the _apsk of an enrollment it does not name
    Given @alice's enrollment G publishes an _apsk listing its own key
    When the verifier checks the envelope against PublishedApsk(atSign: "@alice", enrollmentId: G, value: G's _apsk)
    Then the result is EnvelopeRefused with wrongEnrollment, naming E, G and kid K

  @impersonation
  Scenario: An envelope that names no enrollment is refused
    Given an application envelope signed with K whose protected header names iss "@alice" and no enid
    When the verifier checks it against PublishedApsk(atSign: "@alice", enrollmentId: E, value: E's _apsk)
    Then the result is EnvelopeRefused with wrongEnrollment, saying the envelope names no enrollment, and naming kid K

  @forgery
  Scenario: An envelope signed for another purpose is refused
    Given an envelope a client of E signed as a key package, typed at-key-package+jws
    When the verifier checks it against E's _apsk
    Then the result is EnvelopeRefused with wrongType, naming at-key-package+jws, at-app+jws and kid K

  Scenario Outline: A malformed or truncated _apsk is refused with a reason
    Given E's _apsk value as the verifier holds it is <value>
    When the verifier checks the envelope against it
    Then the result is EnvelopeRefused with malformedKeySet, naming kid K and <fault>

    Examples:
      | value                                               | fault                             |
      | a bare RSA-2048 key truncated by one character      | the value is not base64           |
      | a bare value carrying a character outside base64    | the value is not base64           |
      | an array truncated halfway                          | the value is not valid JSON       |
      | an array whose one entry's pub is truncated         | the entry's key is not base64     |
      | an array listing only an algorithm this build lacks | no key this build can verify with |
      | the empty string                                    | the value is empty                |

  Scenario: verifyEnvelopeSignature refuses an _apsk that cannot be read
    Given @alice's atServer serves E's _apsk as a bare value truncated by one character
    When a client of @bob calls verifyEnvelopeSignature(envelope, signerAtSign: "@alice")
    Then it throws AtSigningVerificationException naming the _apsk

  Scenario: A key package whose enrollment's _apsk cannot be read is rejected
    Given @alice's enrollment E advertises a signed key package, and its _apsk is a bare value carrying a character outside base64
    When another enrollment of @alice reads it with verifyAdvertisedKeyPackage
    Then the status is KeyPackageStatus.rejected

  Scenario: A key the owner retired still verifies, and says so
    Given E rotated, so its _apsk lists K as retired beside its successor K2 as active
    When the verifier checks an envelope K signed before the rotation
    Then the result is EnvelopeVerified naming kid K with key status retired

  Scenario: A key the _apsk does not list is refused
    Given E later published an _apsk listing K2 and not K, and the verifier holds only that value
    When it checks an envelope K signed
    Then the result is EnvelopeRefused with keyNotInKeySet, naming kid K and K2

  @forgery
  Scenario: A key the _apsk lists under a status this build does not know is refused
    Given E's _apsk lists K under the status "suspended", which this build does not know, beside an active K2
    When the verifier checks an envelope K signed
    Then the result is EnvelopeRefused with keyNotVouchedFor, naming kid K and the status "suspended"

  @race
  Scenario: An envelope verifies against an _apsk read before its enrollment was revoked
    Given a verifier read E's _apsk at time T0
    And @alice then revoked E, so the atServer moved E's _apsk to public:_apsk.E.r.__e@alice
    When the verifier checks an envelope from E against the value it read at T0
    Then the result is EnvelopeVerified naming kid K

  @forgery
  Scenario: An envelope verifies under the strongest algorithm it shares with the _apsk, and names it
    Given E's _apsk lists an RSA-2048 key R beside K
    And an envelope a client of E signed that carries only an RS256 signature by R
    When the verifier checks it with no minimumAlgorithm
    Then the result is EnvelopeVerified naming kid R and rsa2048

  @forgery
  Scenario: A caller's minimum algorithm refuses an envelope that verifies only under a weaker one
    Given E's _apsk lists an RSA-2048 key R beside K
    And an envelope a client of E signed that carries only an RS256 signature by R
    When the verifier checks it with minimumAlgorithm: SigningAlgoType.mldsa65
    Then the result is EnvelopeRefused with algorithmTooWeak, naming kid R, rsa2048 and mldsa65

  Scenario: selectEnvelopeKey names the key and status verification would use, without the payload
    Given the envelope's signature entries, held without its payload
    When a verifier calls selectEnvelopeKey with them and E's PublishedApsk
    Then the result is EnvelopeKeySelected naming kid K, mldsa65, key status active and issuerConfirmed true

  Scenario: selectEnvelopeKey reports a retired key, so a caller can refuse it at receipt
    Given E's _apsk lists K as retired beside an active K2
    When a verifier calls selectEnvelopeKey with an envelope K signed
    Then the result is EnvelopeKeySelected naming kid K and key status retired, whose key's offeredForNewOperations is false

  Scenario: selectEnvelopeKey refuses an _apsk that cannot be read, without throwing
    Given E's _apsk value as the verifier holds it is an array truncated halfway
    When a verifier calls selectEnvelopeKey with the envelope and it
    Then the result is EnvelopeRefused with malformedKeySet, naming kid K

  Scenario Outline: selectEnvelopeKey and verifySignedEnvelope choose the same key
    Given E's _apsk lists <listed>, and an envelope a client of E signed carries <carried>
    When a verifier calls selectEnvelopeKey and then verifySignedEnvelope with the same envelope and PublishedApsk
    Then both give <outcome>

    Examples:
      | listed                  | carried                                                 | outcome                                |
      | K and an RSA-2048 key R | an ML-DSA-65 signature by K and an RS256 signature by R | kid K                                  |
      | R only                  | an ML-DSA-65 signature by K and an RS256 signature by R | kid R                                  |
      | K only                  | an RS256 signature by R only                            | EnvelopeRefused with keyNotInKeySet    |

  Scenario Outline: TestEnvelopeSigner signs offline an envelope its PublishedApsk verifies
    Given a test that imports only package:at_client_cli/at_client_cli.dart and package:at_client_cli/testing.dart
    When it builds TestEnvelopeSigner(atSign: "@alice", enrollmentId: E, algorithm: <algorithm>), signs a payload with sign, and verifies the envelope against its publishedApsk
    Then the result is EnvelopeVerified naming @alice, E, <algorithm>, key status active and issuerConfirmed true

    Examples:
      | algorithm                |
      | SigningAlgoType.mldsa65  |
      | SigningAlgoType.rsa2048  |

  Scenario Outline: TestEnvelopeSigner lists its key under a status a test chooses
    Given a TestEnvelopeSigner for "@alice" and E whose publishedApsk lists its key <listing>
    When a test verifies an envelope it signed against that publishedApsk
    Then the result is <result>

    Examples:
      | listing                           | result                                              |
      | as retired                        | EnvelopeVerified with key status retired            |
      | under the unknown status "paused" | EnvelopeRefused with keyNotVouchedFor, naming "paused" |

  @replay
  Scenario: The same envelope presented twice verifies twice
    Given an envelope that verified against E's _apsk
    When the same bytes are presented again, by the same or another party
    Then the result is EnvelopeVerified again, naming the same Atsign, enrollment, kid, algorithm and key status

  @dos
  Scenario: Envelope text over the caller's bound in UTF-8 bytes is refused before it is decoded
    Given envelope text of 40000 characters that is 70000 bytes in UTF-8, and is not JSON
    When the verifier calls SignedEnvelope.parse(text, maxLength: 65536)
    Then it throws AtSigningVerificationException naming the bound of 65536 bytes rather than a JSON error

  @dos
  Scenario: An _apsk value over the cap is refused before it is read
    Given an _apsk value one byte longer than maxPublishedApskLength, which is not valid JSON
    When the verifier checks the envelope against it
    Then the result is EnvelopeRefused with oversize, naming the cap

# Unit tests, not scenarios (canonical comparison stays out of the spec):
#
# group('Given a PublishedApsk built from "@Alice", "alice" or "@alice"')
#   test('when it is read, then its atSign is "@alice"')
# group('Given an envelope whose iss is "@Alice"')
#   test('when verified against PublishedApsk(atSign: "alice"), then it verifies with issuerConfirmed true')
# group('Given an envelope whose iss is not an Atsign')
#   test('when verified, then it is refused with wrongAtSign and nothing is thrown')
# group('Given an envelope whose enid differs from the supplied enrollment id only in case')
#   test('when verified, then it is not refused with wrongEnrollment')
# group('Given fetchPublishedApsk called with "@ALICE"')
#   test('when it returns, then its atSign is "@alice"')
# group('Given any malformed envelope or _apsk value')
#   test('when verified or selected, then an EnvelopeRefused is returned and nothing is thrown')
# group('Given an envelope refused for its type, Atsign, enrollment or algorithm whose signature is also corrupted')
#   test('when verified, then the refusal is that one and not badSignature')
# group('Given an envelope carrying 1,000 RS256 entries')
#   test('when verified, then exactly one public-key verification runs')
#   test('when selected, then no public-key verification runs')

Feature: Every envelope names its signer's Atsign

  Every envelope at_client signs carries its signer's Atsign as iss in each
  protected header: the canonical Atsign with its "@", after kid and before
  enid. The header version stays 1, so at_client 4.0.0 verifies these
  envelopes. SignedEnvelope.fromJson refuses an envelope whose entries name
  different Atsigns, or where one entry names an Atsign and another names
  none. at_client's own verifiers, EnvelopeSigning.verifyEnvelopeSignature
  among them, compare iss with the Atsign they verify for, both canonical,
  and refuse a different one before fetching any _apsk. They accept an
  envelope that names no Atsign, as at_client 4.0.0 signed them, until the
  release that re-signs what an enrollment publishes; verifySignedEnvelope
  accepts one too, and reports issuerConfirmed false.

  Races: none new; the claim is fixed when the envelope is signed, and the
  comparison reads no shared state.
  Replay: none new; an envelope verifies as often as it is presented, as
  before, and names the same Atsign each time.
  DoS: the comparison is a string comparison, made before any _apsk is
  fetched or any signature is checked.
  Forgery and impersonation: the Atsign is inside the protected header, so
  the signature covers it, and a verifier compares it with the Atsign whose
  _apsk the signature is checked against.

  Background:
    Given @alice's enrollment E publishes an _apsk listing one active ML-DSA-65 client data signing key K

  Scenario Outline: Every envelope at_client signs names its signer's Atsign
    Given a client of E
    When it signs <document> through <signer>
    Then every protected header of the envelope names iss "@alice", and the envelope's signerAtSign is "@alice"

    Examples:
      | document                          | signer                                 |
      | an application payload            | EnvelopeSigning.wrapAndSign            |
      | a chain link                      | PqSigningChain.signChainLink           |
      | a key package at enroll:request   | enrollmentKeyPackageBuilder            |
      | a key package at enroll:update    | KeyPackageMinting                      |
      | its nskey advertisement           | PublishedNskeyKeyRing.mintAndPublish   |
      | a secret envelope                 | AtClientSecretSharing                  |
      | its verified-advertisement record | VerifiedAdvertisementRecord.remember   |

  Scenario: An application envelope's header names the Atsign after the key and before the enrollment
    Given a client of E
    When it signs a payload with EnvelopeSigning.wrapAndSign
    Then each protected header's members are alg, typ, kid, iss, enid and v, in that order, and v is 1

  Scenario: An envelope that names its Atsign verifies on at_client 4.0.0
    Given an envelope a client of E signed with wrapAndSign on this release
    When at_client 4.0.0's verifier checks it against E's _apsk as an application envelope
    Then it verifies

  @forgery @impersonation
  Scenario Outline: An envelope whose entries disagree about the Atsign is refused when read
    Given an envelope with one entry naming iss "@alice" and another <other>
    When it is read with SignedEnvelope.fromJson
    Then it throws AtSigningVerificationException naming both entries' claims

    Examples:
      | other             |
      | naming iss "@bob" |
      | naming no iss     |

  @forgery @impersonation
  Scenario: verifyEnvelopeSignature refuses an envelope naming another Atsign
    Given an envelope a client of E signed, naming iss "@alice"
    When a client calls verifyEnvelopeSignature(envelope, signerAtSign: "@bob")
    Then it throws AtSigningVerificationException naming "@alice" and "@bob", and fetches no _apsk

  Scenario: verifyEnvelopeSignature accepts an envelope that names no Atsign
    Given an envelope a client of E signed with at_client 4.0.0, naming enid E and no iss
    When a client calls verifyEnvelopeSignature(envelope, signerAtSign: "@alice")
    Then it completes without throwing

  @forgery @impersonation
  Scenario Outline: at_client's own verifiers refuse a document naming another Atsign
    Given <document> signed by a client of E, naming iss "@alice"
    When it is checked as @bob's through <verifier>
    Then <outcome>

    Examples:
      | document                 | verifier                                          | outcome                                                              |
      | an nskey advertisement   | ApkamSignedAdvertisedKeys.verify("@bob", it)      | it throws AtSigningVerificationException naming "@alice" and "@bob"  |
      | a key package            | verifyAdvertisedKeyPackage(signerAtSign: "@bob")  | the status is KeyPackageStatus.rejected                              |
      | a chain link on a key    | PqSigningChain.verifyChain                        | the verdict is ChainVerdict.broken, with a reason naming "@alice"    |

  Scenario Outline: at_client's own verifiers accept a document that names no Atsign
    Given <document> signed by a client of E with at_client 4.0.0, naming no iss
    When it is checked as @alice's through <verifier>
    Then <outcome>

    Examples:
      | document                 | verifier                                          | outcome                                      |
      | an nskey advertisement   | ApkamSignedAdvertisedKeys.verify("@alice", it)    | it returns the advertisement                 |
      | a key package            | verifyAdvertisedKeyPackage(signerAtSign: "@alice")| the status is KeyPackageStatus.present       |
      | a chain link on a key    | PqSigningChain.verifyChain                        | the verdict is not ChainVerdict.broken       |

# Unit tests, not scenarios (canonical comparison stays out of the spec):
#
# group('Given a client whose current Atsign is spelt "@Alice"')
#   test('when it signs, then iss is "@alice"')
# group('Given an envelope whose iss is "@Alice"')
#   test('when verifyEnvelopeSignature checks it with signerAtSign "ALICE", then it verifies')
# group('Given an envelope whose iss is not an Atsign')
#   test('when verifyEnvelopeSignature checks it, then it throws AtSigningVerificationException naming the claim')
# group('Given an envelope whose entries name "@alice" and "@Alice"')
#   test('when it is read with SignedEnvelope.fromJson, then it is accepted as one signer')

Feature: An enrolment can use an APKAM keypair the caller supplies
  An AtEnrollmentRequest may carry apkamKeyPair, the two halves of the
  APKAM authentication keypair the enrollment is to authenticate with, in
  place of letting at_auth mint one. The pair is checked before anything is
  sent: both halves are base64, the private half signs a fixed string through
  the signer a pkam: uses, and the signature verifies against the public half.
  Both halves are then canonicalised to standard base64, so the request, _apsk
  and the keyfile all spell the key the same way. A pair that fails is refused
  with AtSigningException and no enroll:request is sent, because the atServer
  would accept it, answer every later pkam: with AT0401 (which waitForApproval
  reads as "not decided yet"), and refuse to enrol that public key again while
  the record exists.

  Replay: nothing is issued or checked. Denial of service: one signature and
  one verification per supplied pair. Forgery and impersonation: whoever
  supplies the pair decides the enrollment's client authentication signing
  key, so the pair must come from the enrolling device.

  Scenario: A supplied pair is the one enrolled
    Given an AtEnrollmentRequest carrying a matching mldsa65 or rsa2048 pair
    When it is submitted
    Then the request's apkamPublicKey and _apsk carry the supplied public key
    And the keyfile holds the supplied private key
    And for rsa2048 the flat fields keep the pair and no typed material is filed

  Scenario: An absent pair is minted
    Given an AtEnrollmentRequest carrying no apkamKeyPair
    When it is submitted
    Then a fresh keypair is minted under the request's signingAlgo

  Scenario: A pair whose halves belong to different keypairs is refused
    Given an AtEnrollmentRequest carrying the public half of one keypair and
      the private half of another, for mldsa65 or rsa2048
    When it is submitted
    Then it fails with AtSigningException
    And no enroll:request is sent

  Scenario: An empty or all-zero pair is refused
    Given an AtEnrollmentRequest carrying an mldsa65 pair of all-zero bytes
      or an rsa2048 pair of two empty strings
    When it is submitted
    Then it fails with AtSigningException
    And no enroll:request is sent

  Scenario: A base64url pair is enrolled in standard base64
    Given an AtEnrollmentRequest carrying a matching pair spelled base64url
    When it is submitted
    Then the request, _apsk and the keyfile carry the standard-base64 spelling

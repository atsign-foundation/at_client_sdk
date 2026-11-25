Feature: Onboarding a new atSign runs the passkey ceremonies before the atServer

  onboardNewAtSign registers a passkey, derives the atSign's keys from its PRF
  output and activates the atSign at its atServer. The entry point takes only
  SessionTransportOptions, which names a real `wss://` atServer; there is no
  seam to hand it a fake EnrollmentGateway, pointer reader or lookup factory
  the way PasskeyCustody takes one. Its activation also polls an unreachable
  atServer for the whole onboarding provisioning budget (five minutes) before
  it throws, so a suite with no atServer can prove the chain only up to the
  first dial. The enrolment request, the approval, the PKAM and the client's
  first read are proven at the PasskeyCustody seam instead, by a fake gateway
  (see passkey_custody_browser_test.dart).

  Scenario: onboarding a new atSign runs the PRF ceremonies and then reaches the atServer
    Given a faked navigator.credentials whose create reports PRF enabled and whose get returns 32 bytes
    And a bound loopback port whose connections are destroyed as they arrive
    When the app onboards @alice through onboardNewAtSign with the transport pointed at that port
    Then it runs one create ceremony named for @alice and one PRF assertion narrowed to that credential
    And the atServer at that port receives a connection
    And this browser keeps no passkey hints for @alice before the atServer answers

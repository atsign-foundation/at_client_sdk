Feature: onboarding enroll test
  Scenario: Initial onboarding with enableEnrollmentDuringOnboard flag set
    Given New atsign is activated
    And secondary server is running

    When Onboarding is attempted with the below preference
      | Field | Value |
      | enableEnrollmentDuringOnboard | true |
    Then onboarding should be successful
    And onboard method should return true
    And .atKeys file should be generated in the specified location
    And .atKey file should store enrollmentId and apkamSymmetricKey

    When authenticate is done in onboarding service
    Then auth method should return true

  ## negative test
  Scenario: Initial onboarding with enableEnrollmentDuringOnboard flag set - params missing
    Given New atsign is activated
    And secondary server is running

    When Onboarding is attempted without passing appName or deviceName
    Then onboard method should throw AtOnboardingException

  Scenario: Check Otp verb on onboarded and authenticated client
    Given A cli client is onboarded and authenticated
    When otp verb is executed using at client
    Then otp verb should return a string
    And otp should contain alpha numeric string
    And should have length of 6
    And should not have 0 or o

  Scenario: New onboarding cli client requests for enrollment
    Given A privileged client exists for an atsign to approve/deny enrollment
    When New cli client requests for an enrollment
      | Field | Value |
      | appName | buzz |
      | deviceName | iphone |
      | namespaces | {buzz,rw} |
      | otp        | <result of otp:get>|
    Then enroll method should return successful
    And AtEnrollmentResponse.enrollmentId should be non null
    And AtEnrollmentResponse.enrollStatus should be pending

    When A privileged client gets the notification
    Then notification should contain enrollmentId, encryptedApkamSymmetricKey

    When privileged client send enroll:approve request
    Then enroll response from server should contain enrollStatus='approved' and enrollmentId

    When A privileged client approves the enrollment notification
    Then Cli client requesting for enrollment will retry pkam auth in the background
    And atKeys file gets generated for the cli client requesting enrollment
    And atKeys file should store enrollmentId, apkamSymmetricKey, apkam public and private key
    And cli client should be able to authenticate with the keys file

    When A privileged client gets the notification
    Then notification should contain enrollmentId, encryptedApkamSymmetricKey

    When privileged client send enroll:deny request
    Then enroll response from server should contain enrollStatus='denied' and enrollmentId
    And auth attempt from the client should fail

  Scenario: New onboarding cli client requests for enrollment with invalid otp
    Given A privileged client exists for an atsign to approve/deny enrollment
    When New cli client requests for an enrollment
      | Field | Value |
      | appName | buzz |
      | deviceName | iphone |
      | namespaces | {buzz,rw} |
      | otp        | <invalid otp> |
    Then server should deny the request with invalid otp error response

    #To be tested manually since otp timeout on server is 1 min
  Scenario: New onboarding cli client requests for enrollment with valid but timed out otp
    Given A privileged client exists for an atsign to approve/deny enrollment
    When New cli client requests for an enrollment
      | Field | Value |
      | appName | buzz |
      | deviceName | iphone |
      | namespaces | {buzz,rw} |
      | otp        | <valid but timed out otp> |
    Then server should deny the request with invalid otp error response
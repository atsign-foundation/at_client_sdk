Feature: Atclient enrollment test
      Scenario: Verify enrollment request returns notification
            Given Atsign is cram authenticated
            When Enroll request command is sent to the server with the following
                  | Field                               | Value                                          |
                  | appName                             | buzz                                           |
                  | deviceName                          | iphone                                         |
                  | namespaces                          | {buzz,rw}                                      |
                  | encryptedDefaultEncryptedPrivateKey | <atsign's encryptedDefaultEncryptedPrivateKey> |
                  | encryptedDefaultSelfEncryptionKey   | <atsign's encryptedDefaultSelfEncryptionKey    |
                  | apkamPublicKey                      | <atsign's apkamPublicKey                       |
            Then the response from the server should not be empty
            And the enrollment ID and status in the response should be:
                  | Field        | Value    |
                  | enrollmentId | NotEmpty |
                  | status       | approved |

            When the client fetches OTP(otp:get) from the remote secondary
            Then the OTP response should not be empty
            And the OTP should be extracted from the response

            When a new enroll request is sent with OTP and the APKAM public key
                  | Field          | Value                    |
                  | appName        | buzz                     |
                  | deviceName     | iphone                   |
                  | namespaces     | {buzz,rw}                |
                  | otp            | <result of otp:get>      |
                  | apkamPublicKey | <atsign's apkamPublicKey |
                  | encryptedApkamSymmetricKey | apkam symmetric key encrypted with default encryption public key|
            And the request is executed on a new remote secondary
            Then the enrollment response should not be empty
            And the enrollment ID and status in the response should be:
                  | Field        | Value    |
                  | enrollmentId | NotEmpty |
                  | status       | pending  |

            When the privileged client subscribes to enrollment notification
            Then the client should receive one enrollment notification
            And the enrollNotification.key should match the enrollment ID from the server response
            And Then notification should contain enrollmentId, encryptedApkamSymmetricKey


      Scenario: Validate client functionality to fetch pending enrollments on legacy pkam authenticated client
            Given Atsign is cram authenticated
            When the client fetches the first OTP (otp:get)
            Then the OTP should not be null

            And the client creates the first enrollment request with the fetched OTP and APKAM public key
                  | Field          | Value                    |
                  | appName        | new_app                  |
                  | deviceName     | pixel                    |
                  | namespaces     | {"new_app":"rw"}         |
                  | otp            | <result of otp:get>      |
                  | apkamPublicKey | <atsign's apkamPublicKey |
            Then the response from the server should not be empty
            And the enrollment ID and status in the response should be:
                  | Field        | Value    |
                  | enrollmentId | NotEmpty |
                  | status       | approved |

            When the client fetches the second OTP(otp:get) from the remote secondary
            Then the OTP response should not be null

            When the client creates the second enrollment request with the fetched OTP and APKAM public key
                  | Field          | Value                        |
                  | appName        | new_app                      |
                  | deviceName     | pixel7                       |
                  | namespaces     | {"new_app":"rw", "wavi":"r"} |
                  | otp            | <result of otp:get>          |
                  | apkamPublicKey | <atsign's apkamPublicKey     |
            Then the enrollment response should not be null
            And the enrollment ID and status in the response should be:
                  | Field        | Value    |
                  | enrollmentId | NotEmpty |
                  | status       | pending  |

            When the client fetches enrollment requests
            Then the number of enrollment requests(enrollmentRequests.length) should be 4

            And the client verifies the details of each enrollment request
                  | Enrollment ID       | Namespace            | Device Name | Status  |
                  | firstEnrollmentKey  | new_app: rw          | pixel       | pending |
                  | secondEnrollmentKey | new_app: rw, wavi: r | pixel7      | pending |
            And the list should contain exactly two matches for enrollment requests

      Scenario: Invalid OTP
            Given Atsign's new client is not enrolled
            When new enrollment is submitted with invalid otp
            Then server rejects the enrollment
            And server response should contain
                  | Field        | Value    |
                  | errorCode | AT0011 |
                  | errorMessage       | invalid otp. Cannot process enroll request  |

      Scenario: Already used OTP cannot be used again
            Given New client enroll's with a OTP and enrollment is in pending state
            When the same client requests for new enrollment with the already used OTP
            Then server reject the enrollment
            And server response should contain
                  | Field        | Value    |
                  | errorCode | AT0011 |
                  | errorMessage       | invalid otp. Cannot process enroll request  |
List of steps to run the examples for checking apkam enrollment

1. Onboard an atsign which will get the privilege to approve/deny enrollments:<br>
   - run: `dart example/onboard.dart -a <atsign> -c <CRAM secret> -k <path_store_keys_file>`<br>
   - e.g. `dart example/onboard.dart -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys -c b26455a907582760ebf35bc4847de549bc41c24b25c8b1c58d5964f7b4f8a43bc55b0e9a601c9a9657d9a8b8bbc32f88b4e38ffaca03c8710ebae1b14ca9f364`<br/>
   - If you do not already have the CRAM Secret for your atsign
     run: `dart example/get_cram_key.dart -a <@atsign>`
2. Authenticate using the onboarded atsign:<br>
   - run: `dart example/apkam_examples/apkam_authenticate.dart -a <atsign> -k <path_of_keys_file_from_#1>`<br>
   - e.g. `dart example/apkam_examples/apkam_authenticate.dart -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys`
3. Run client to approve enrollments:<br>
   - run: `dart example/apkam_examples/enroll_app_listen.dart -a <atsign> -k <path_of_keys_file_from_#1>`<br>
   - e.g `dart example/apkam_examples/enroll_app_listen.dart -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys`
4. Get OTP for enrollment
    - 4.1 Perform a PKAM authentication through the ssl client
      - 4.1.1 Get the challenge from the atServer:<br>
        - run: `from:<@atsign>` e.g. `from:@alice` <br>
        - This generates a string which is called the challenge which will be used to generate the authentication token<br>
      - 4.1.2 Create a pkamSignature that can be used to authenticate yourself<br>
        - Clone at_tools from https://github.com/atsign-foundation/at_tools.git
        - Change directory into 'at_tools/packages/at_pkam>'<br>
        - run: `dart bin/main.dart -p <keys_file_path> <from_response>`<br>
        - e.g `dart bin/main.dart -p /home/alice/.atsign/@alice_wavikey.atKeys -r _70138292-07b5-4e47-8c94-e02e38220775@alice:883ea0aa-c526-400a-926e-48cae9281de9`<br>
        - This should generate a hash, which is called the pkamSignature which will be used to authenticate into the atServer<br>
      - 4.1.3 Now that a pkamSignature is generated, use it to authenticate<br>
        run:`pkam:enrollmentId:<enrollmentId>:<pkamSignature>` [enrollmentId - get it from the .atKeys file]<br>
    - 4.2 Once authenticated run `otp:get`<br>
      - Now copy the 6-digit alpha-numeric code which is the OTP
5. Request enrollment
    - 5.1 Submit enrollment from new client:<br>
      - run:`dart example/apkam_examples/apkam_enroll.dart -a <atsign> -k <path_to_store_keys_file> -o <otp>`<br>
      - Note: this path has to be different from the path provided in Step#1 as this is a new file
      - e.g. `dart example/apkam_examples/apkam_enroll.dart -a @alice -k /home/alice/.atsign/@alice_buzzkey.atKeys -o DY4UT4`<br>
    - 5.2 Approve the enrollment from the client from #3<br>
      - To approve the enrollment type `yes` and then Enter
    - 5.3 Enrollment should be successful and atKeys file stored in the path specified
6. Authenticate using the enrolled keys file<br>
    - 6.1 run: `dart example/apkam_examples/apkam_authenticate.dart -a <atsign> -k <path_of_keys_file_from_#5.1>`
    - Note: this keys file is different from the keys file generated in Step#1. This new file only has access to the data that is allowed to access from this enrollment_id
       

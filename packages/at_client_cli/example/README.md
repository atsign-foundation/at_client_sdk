List of steps to run the examples for checking apkam enrollment

1. Onboard an atsign which will get the privilege to approve/deny enrollments:<br>
   - run: `dart example/bin/onboard.dart -a <atsign> -c <CRAM secret> -k <path_store_keys_file>`<br>
   - e.g. `dart example/bin/onboard.dart -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys -c b26455a907582760ebf35bc4847de549bc41c24b25c8b1c58d5964f7b4f8a43bc55b0e9a601c9a9657d9a8b8bbc32f88b4e38ffaca03c8710ebae1b14ca9f364`<br/>
   - If you do not already have the CRAM Secret for your atsign, run
     `at_activate onboard -a <@atsign>` instead: the registrar emails a verification code, and at_activate fetches the secret with it
2. Authenticate using the onboarded atsign:<br>
   - run: `dart example/bin/apkam_examples/apkam_authenticate.dart -a <atsign> -k <path_of_keys_file_from_#1>`<br>
   - e.g. `dart example/bin/apkam_examples/apkam_authenticate.dart -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys`
3. Run client to approve enrollments:<br>
   - run: `dart example/bin/apkam_examples/enroll_app_listen.dart -a <atsign> -k <path_of_keys_file_from_#1>`<br>
   - e.g `dart example/bin/apkam_examples/enroll_app_listen.dart -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys`
4. Get OTP for enrollment
    - run: `at_activate otp -a <atsign> -k <path_of_keys_file_from_#1>`, which prints the OTP<br>
    - e.g. `at_activate otp -a @alice -k /home/alice/.atsign/@alice_wavikey.atKeys`<br>
    - Add `-r <host:port>` for an atSign outside the production atDirectory
5. Request enrollment
    - 5.1 Submit enrollment from new client:<br>
      - run:`dart example/bin/apkam_examples/apkam_enroll.dart -a <atsign> -k <path_to_store_keys_file> -o <otp>`<br>
      - Note: this path has to be different from the path provided in Step#1 as this is a new file
      - e.g. `dart example/bin/apkam_examples/apkam_enroll.dart -a @alice -k /home/alice/.atsign/@alice_buzzkey.atKeys -o DY4UT4`<br>
    - 5.2 Approve the enrollment from the client from #3<br>
      - To approve the enrollment type `yes` and then Enter
    - 5.3 Enrollment should be successful and atKeys file stored in the path specified
6. Authenticate using the enrolled keys file<br>
    - 6.1 run: `dart example/bin/apkam_examples/apkam_authenticate.dart -a <atsign> -k <path_of_keys_file_from_#5.1>`
    - Note: this keys file is different from the keys file generated in Step#1. This new file only has access to the data that is allowed to access from this enrollment_id
       

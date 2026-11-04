// Throwaway probe: an ad-hoc dylib whose constructor reads a probe item from
// inside whatever process loads it, then exits before that process's own code
// runs. run_signed.sh injects it into a team-signed binary with
// DYLD_INSERT_LIBRARIES to measure whether the binary's entitlements let a
// same-user process borrow its code identity. Prints raw measurements only.
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor)) static void probe_inject(void) {
  const char *service = getenv("KCPROBE_INJECT_SERVICE");
  if (service == NULL) return;
  SecKeychainSetUserInteractionAllowed(false);
  CFStringRef svc = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
  const void *keys[] = {kSecClass, kSecAttrService, kSecAttrAccount,
                        kSecReturnData, kSecMatchLimit};
  const void *vals[] = {kSecClassGenericPassword, svc, CFSTR("probe"),
                        kCFBooleanTrue, kSecMatchLimitOne};
  CFDictionaryRef query =
      CFDictionaryCreate(NULL, keys, vals, 5, &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  CFTypeRef out = NULL;
  OSStatus rc = SecItemCopyMatching(query, &out);
  long n = (rc == errSecSuccess && out != NULL) ? CFDataGetLength(out) : -1;
  printf("PROBE injected mode=read status=%d bytes=%ld\n", (int)rc, n);
  fflush(stdout);
  exit(0);
}

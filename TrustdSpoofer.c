// TrustdSpoofer.c
#include <stdio.h>
#include <Security/Security.h>

__attribute__((constructor))
static void init() {
    syslog(LOG_NOTICE, "TrustdSpoofer 已加载");
}

OSStatus hooked_SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
    if (result) *result = kSecTrustResultUnspecified;
    return errSecSuccess;
}

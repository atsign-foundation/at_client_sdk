#import "AtInvitationFlutterPlugin.h"
#if __has_include(<at_invitation_flutter/at_invitation_flutter-Swift.h>)
#import <at_invitation_flutter/at_invitation_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "at_invitation_flutter-Swift.h"
#endif

@implementation AtInvitationFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAtInvitationFlutterPlugin registerWithRegistrar:registrar];
}
@end

#import "AtChatFlutterPlugin.h"
#if __has_include(<at_chat_flutter/at_chat_flutter-Swift.h>)
#import <at_chat_flutter/at_chat_flutter-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "at_chat_flutter-Swift.h"
#endif

@implementation AtChatFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAtChatFlutterPlugin registerWithRegistrar:registrar];
}
@end

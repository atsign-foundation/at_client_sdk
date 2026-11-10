// Throwaway probe: store and read a generic-password item in the macOS login
// keychain through Security.framework, with user interaction disabled so an
// access prompt surfaces as errSecInteractionNotAllowed (-25308) rather than
// a dialog. Prints raw measurements only.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const buildTag = 'v1';

final cf = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
final sec =
    DynamicLibrary.open('/System/Library/Frameworks/Security.framework/Security');

Pointer<Void> sym(DynamicLibrary l, String n) => l.lookup<Pointer<Void>>(n).value;

final cfStr = cf.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
    Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)>(
  'CFStringCreateWithCString');
final cfDataCreate = cf.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Long),
    Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)>('CFDataCreate');
final cfDataLen = cf.lookupFunction<Long Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CFDataGetLength');
final cfDataPtr = cf.lookupFunction<Pointer<Uint8> Function(Pointer<Void>),
    Pointer<Uint8> Function(Pointer<Void>)>('CFDataGetBytePtr');
final cfDict = cf.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>, Long, Pointer<Void>, Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>,
        Pointer<Pointer<Void>>, int, Pointer<Void>, Pointer<Void>)>(
  'CFDictionaryCreate');

final secAdd = sec.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
    int Function(Pointer<Void>, Pointer<Pointer<Void>>)>('SecItemAdd');
final secCopy = sec.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
    int Function(Pointer<Void>, Pointer<Pointer<Void>>)>('SecItemCopyMatching');
final secDelete = sec.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('SecItemDelete');
final secSetUi = sec.lookupFunction<Int32 Function(Uint8), int Function(int)>(
    'SecKeychainSetUserInteractionAllowed');


final secAccessCreate = sec.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>),
    int Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>)>(
  'SecAccessCreate');
final secAccessMatchingAcls = sec.lookupFunction<
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
    Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>(
  'SecAccessCopyMatchingACLList');
final secAclCopy = sec.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>,
        Pointer<Uint16>),
    int Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>,
        Pointer<Uint16>)>('SecACLCopyContents');
final secAclSet = sec.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Uint16),
    int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, int)>(
  'SecACLSetContents');
final cfArrayCount = cf.lookupFunction<Long Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CFArrayGetCount');
final cfArrayAt = cf.lookupFunction<Pointer<Void> Function(Pointer<Void>, Long),
    Pointer<Void> Function(Pointer<Void>, int)>('CFArrayGetValueAtIndex');

/// A SecAccess whose decrypt ACL entries list no applications: any app.
(Pointer<Void>, String) anyAppAccess() {
  final out = calloc<Pointer<Void>>();
  final rc = secAccessCreate(s('atsign-kc-probe'), nullptr, out);
  final acls = secAccessMatchingAcls(
      out.value, sym(sec, 'kSecACLAuthorizationDecrypt'));
  final n = acls == nullptr ? -1 : cfArrayCount(acls);
  var setRc = <int>[];
  for (var i = 0; i < n; i++) {
    final acl = cfArrayAt(acls, i);
    final apps = calloc<Pointer<Void>>();
    final desc = calloc<Pointer<Void>>();
    final prompt = calloc<Uint16>();
    secAclCopy(acl, apps, desc, prompt);
    setRc.add(secAclSet(acl, nullptr, desc.value, prompt.value));
  }
  return (out.value, 'accessCreate=$rc decryptAcls=$n aclSet=$setRc');
}

Pointer<Void> s(String v) => cfStr(nullptr, v.toNativeUtf8(), 0x08000100);

Pointer<Void> dict(Map<Pointer<Void>, Pointer<Void>> m) {
  final ks = calloc<Pointer<Void>>(m.length);
  final vs = calloc<Pointer<Void>>(m.length);
  var i = 0;
  m.forEach((k, v) {
    ks[i] = k;
    vs[i] = v;
    i++;
  });
  return cfDict(nullptr, ks, vs, m.length,
      cf.lookup<Void>('kCFTypeDictionaryKeyCallBacks'),
      cf.lookup<Void>('kCFTypeDictionaryValueCallBacks'));
}

Map<Pointer<Void>, Pointer<Void>> base(String service) => {
      sym(sec, 'kSecClass'): sym(sec, 'kSecClassGenericPassword'),
      sym(sec, 'kSecAttrService'): s(service),
      sym(sec, 'kSecAttrAccount'): s('probe'),
      sym(sec, 'kSecUseAuthenticationUI'): sym(sec, 'kSecUseAuthenticationUIFail'),
    };

Uint8List payload(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + 3) % 251));

void main(List<String> args) {
  final uiRc = secSetUi(0);
  final exe = Platform.resolvedExecutable;
  final mode = args[0], service = args[1];
  final sw = Stopwatch()..start();
  if (mode == 'add') {
    final data = payload(int.parse(args[2]));
    final buf = calloc<Uint8>(data.length)..asTypedList(data.length).setAll(0, data);
    final m = base(service)..[sym(sec, 'kSecValueData')] = cfDataCreate(nullptr, buf, data.length);
    final rc = secAdd(dict(m), nullptr);
    print('PROBE build=$buildTag exe=$exe mode=add bytes=${data.length} status=$rc setUi=$uiRc ms=${sw.elapsedMilliseconds}');
  } else if (mode == 'addany') {
    final data = payload(int.parse(args[2]));
    final buf = calloc<Uint8>(data.length)..asTypedList(data.length).setAll(0, data);
    final (access, how) = anyAppAccess();
    final m = base(service)
      ..[sym(sec, 'kSecValueData')] = cfDataCreate(nullptr, buf, data.length)
      ..[sym(sec, 'kSecAttrAccess')] = access;
    final rc = secAdd(dict(m), nullptr);
    print('PROBE build=$buildTag exe=$exe mode=addany bytes=${data.length} status=$rc $how');
  } else if (mode == 'read') {
    final m = base(service)
      ..[sym(sec, 'kSecReturnData')] = sym(cf, 'kCFBooleanTrue')
      ..[sym(sec, 'kSecMatchLimit')] = sym(sec, 'kSecMatchLimitOne');
    final out = calloc<Pointer<Void>>();
    final rc = secCopy(dict(m), out);
    var detail = '';
    if (rc == 0) {
      final n = cfDataLen(out.value);
      final got = cfDataPtr(out.value).asTypedList(n);
      final want = payload(n);
      var same = true;
      for (var i = 0; i < n; i++) {
        if (got[i] != want[i]) { same = false; break; }
      }
      detail = ' bytes=$n contentMatches=$same';
    }
    print('PROBE build=$buildTag exe=$exe mode=read status=$rc$detail setUi=$uiRc ms=${sw.elapsedMilliseconds}');
  } else if (mode == 'delete') {
    final rc = secDelete(dict(base(service)));
    print('PROBE build=$buildTag exe=$exe mode=delete status=$rc');
  }
}

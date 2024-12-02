import 'package:meta/meta.dart';

class VerbSyntax {
  // Adding \{ and \} to regex to ensure the JSON encoded String is Map.
  static const from =
      r'^from:(?<atSign>@?[^:@\s]+)(:clientConfig:(?<clientConfig>\{.+\}))?$';
  static const pol = r'^pol$';
  static const cram = r'^cram:(?<digest>.+$)';
  static const pkam =
      r'^pkam:(signingAlgo:(?<signingAlgo>ecc_secp256r1|rsa2048):)?(hashingAlgo:(?<hashingAlgo>sha256|sha512):)?(enrollmentId:(?<enrollmentId>.+):)?(?<signature>.+$)';
  static const llookup = r'^llookup'
      r'(:(?<operation>meta|all))?'
      r'(:cached)?'
      r'(:((?<publicScope>public)|(@(?<forAtSign>[^:@\s]+))))?'
      r':(?<atKey>[^:]((?!:{2})[^@])+)'
      r'@(?<atSign>[^:@\s]+)$';
  static const plookup =
      r'^plookup:(bypassCache:(?<bypassCache>true|false):)?((?<operation>meta|all):)?(?<atKey>[^@\s]+)@(?<atSign>[^:@\s]+)$';
  static const lookup =
      r'^lookup:(bypassCache:(?<bypassCache>true|false):)?((?<operation>meta|all):)?(?<atKey>(?:[^:]).+)@(?<atSign>[^:@\s]+)$';
  static const scan =
      r'^scan$|scan(:showhidden:(?<showhidden>true|false))?(:(?<forAtSign>@[^:@\s]+))?(:page:(?<page>\d+))?( (?<regex>\S+))?$';
  static const config =
      r'^config:(?:(?<=config:)block:(?<operation>add|remove|show)(?:(?<=show)\s?$|(?:(?<=add|remove):(?<atSign>(?:@[^:@\s]+)( (?:@[^\s@]+))*$))))|(?:(?<=config:)(?<setOperation>set|reset|print):(?<configNew>.+)$)';
  static const stats =
      r'^stats(?<statId>:((?!0)\d+)?(,(\d+))*)?(:(?<regex>(?<=:3:|:15:).+))?$';
  static const sync = r'^sync:(?<from_commit_seq>[0-9]+|-1)(:(?<regex>.+))?$';
  static const syncFrom =
      r'^sync:from:(?<from_commit_seq>[0-9]+|-1)(:limit:(?<limit>\d+))?(:skipDeletesUntil:(?<skipDeletesUntil>\d+))?(:(?<regex>.+))?$';

  @visibleForTesting
  static const metadataFragment = r'(:ttl:(?<ttl>(-?)\d+))?'
      r'(:ttb:(?<ttb>(-?)\d+))?'
      r'(:ttr:(?<ttr>(-?)\d+))?'
      r'(:ccd:(?<ccd>true|false))?'
      r'(:dataSignature:(?<dataSignature>[^:@\s]+))?'
      r'(:sharedKeyStatus:(?<sharedKeyStatus>[^:@\s]+))?'
      r'(:isBinary:(?<isBinary>true|false))?'
      r'(:isEncrypted:(?<isEncrypted>true|false))?'
      r'(:sharedKeyEnc:(?<sharedKeyEnc>[^:@\s]+))?'
      r'(:pubKeyCS:(?<pubKeyCS>[^:@\s]+))?'
      r'(:pubKeyHash:(?<pubKeyHash>[^:@\s]+))?'
      r'(:hashingAlgo:(?<hashingAlgo>[^:@\s]+))?'
      r'(:encoding:(?<encoding>[^:@\s]+))?'
      r'(:encKeyName:(?<encKeyName>[^:@\s]+))?'
      r'(:encAlgo:(?<encAlgo>[^:@\s]+))?'
      r'(:ivNonce:(?<ivNonce>[^:@\s]+))?'
      r'(:skeEncKeyName:(?<skeEncKeyName>[^:@\s]+))?'
      r'(:skeEncAlgo:(?<skeEncAlgo>[^:@\s]+))?';

  static const update = r'^update:json:(?<json>.+)$'
      r'|'
      r'^update'
      '$metadataFragment'
      r'(:((?<publicScope>public)|(@(?<forAtSign>[^:@\s]+))))?'
      r':(?<atKey>(([^:@\s]+)|(privatekey:at_pkam_publickey)))'
      r'(@(?<atSign>[^:@\s]+))?'
      r' (?<value>.+)'
      r'$';

  // ignore: constant_identifier_names
  static const update_meta = r'^update:meta'
      r'(:((?<publicScope>public)|(@(?<forAtSign>[^:@\s]+))))?'
      r':(?<atKey>[^:@]((?!:{2})[^:@])+)'
      r'@(?<atSign>[^:@\s]+)'
      '$metadataFragment'
      r'$';
  static const delete = r'^delete'
      r'(:priority:(?<priority>low|medium|high))?'
      r'(:cached)?'
      r'(:((?<publicScope>public)|(@(?<forAtSign>[^:@\s]+))))?'
      r':(?<atKey>(([^:@\s]+)|(privatekey:at_secret)))'
      r'(@(?<atSign>[^:@\s]+))?'
      r'$';

  /// * When 'strict' is set, server will only send notifications which match the regex; no other
  ///   'control' notifications such as statsNotifications will be sent on this connection unless
  ///   they match the regex
  /// * When 'multiplexed' is set, the server will understand that this is a connection
  ///   which the client is using not just for notifications but also for request-response
  ///   interactions. In this case, the server will only send notifications when there is no request
  ///   currently being handled
  /// * When 'epochMillis' is supplied, server will only send notifications received at or after
  ///   that timestamp
  /// * When 'regex' is supplied, server will send notifications which match the regex. If 'strict'
  ///   is set, then only those regex-matching notifications will be sent. If 'strict' is not set,
  ///   then other 'control' notifications (e.g. the statsNotification) which don't necessarily
  ///   match the regex will also be sent
  static const monitor = r'^monitor'
      r'(:(?<strict>strict))?'
      r'(:(?<selfNotifications>selfNotifications))?'
      r'(:(?<multiplexed>multiplexed))?'
      r'(:(?<epochMillis>\d+))?'
      r'( (?<regex>.+))?'
      r'$';
  static const stream =
      r'^stream:((?<operation>init|send|receive|done|resume))?((@(?<receiver>[^@:\s]+)))?( ?namespace:(?<namespace>[\w-]+))?( ?startByte:(?<startByte>\d+))?( (?<streamId>[\w-]*))?( (?<fileName>.* ))?((?<length>\d*))?$';

  static const notify = r'^notify'
      r'(:id:(?<id>[\w\d\-\_]+))?'
      r'(:(?<operation>update|delete))?'
      r'(:messageType:(?<messageType>key|text))?'
      r'(:priority:(?<priority>low|medium|high))?'
      r'(:strategy:(?<strategy>all|latest))?'
      r'(:latestN:(?<latestN>\d+))?'
      r'(:notifier:(?<notifier>[^\s:]+))?'
      r'(:ttln:(?<ttln>\d+))?'
      '$metadataFragment'
      r':((?<publicScope>public)|(@(?<forAtSign>[^:@\s]+)))'
      r':(?<atKey>[^:@]((?!:{2})[^@])+)'
      r'(@(?<atSign>[^:@\s]+))?'
      r'(:(?<value>.+))?'
      r'$';
  static const notifyList =
      r'^notify:list(:(?<fromDate>\d{4}-[01]?\d?-[0123]?\d?))?(:(?<toDate>\d{4}-[01]?\d?-[0123]?\d?))?(:(?<regex>[^:]+))?';
  static const notifyStatus = r'^notify:status:(?<notificationId>\S+)$';
  static const notifyFetch = r'^notify:fetch:(?<notificationId>\S+)$';
  static const notifyAll = r'^notify:all:'
      r'((?<operation>update|delete):)?'
      r'(messageType:((?<messageType>key|text):))?'
      r'(?:ttl:(?<ttl>\d+):)?'
      r'(?:ttb:(?<ttb>\d+):)?'
      r'(?:ttr:(?<ttr>-?\d+):)?'
      r'(?:ccd:(?<ccd>true|false+):)?'
      r'(?<forAtSign>(([^:\s])+)?(,([^:\s]+))*)'
      r'(:(?<atKey>[^@:\s]+))(@(?<atSign>[^@:\s]+))?(:(?<value>.+))?$';
  static const batch = r'^batch:(?<json>.+)$';
  static const info = r'^info(:brief)?$';
  static const noOp = r'^noop:(?<delayMillis>\d+)$';
  static const notifyRemove = r'notify:remove:(?<id>[\w\d\-\_]+)';
  static const enroll =
      // The non-capturing group (?::)? matches ":" if the operation is request|approve|deny|revoke
      r'^enroll:(?<operation>(?:(request|approve|deny|revoke|list|fetch|unrevoke|delete)))(:(?<force>force))?(?::)?((?<enrollParams>.+)|(<=list:)<enrollParams>.?)?$';
  static const otp =
      r'^otp:(?<operation>get|put)(:(?<otp>(?<=put:)\w{6,}))?(:(?:ttl:(?<ttl>\d+)))?$';
  static const keys = r'^keys:((?<operation>put|get|delete):?)'
      r'(?:(?<visibility>public|private|self):?)?'
      r'(?:namespace:(?<namespace>[a-zA-Z0-9_]+):?)?'
      r'(?:appName:(?<appName>[a-zA-Z0-9_]+):?)?'
      r'(?:deviceName:(?<deviceName>[a-zA-Z0-9_]+):?)?'
      r'(?:keyType:(?<keyType>[a-zA-Z0-9_-]+):?)?'
      r'(?:encryptionKeyName:(?<encryptionKeyName>[a-zA-Z0-9_\-]+):?)?'
      r'(?:keyName:(?<keyName>\S+) ?)?'
      r'(?<keyValue>.*)?$';
}

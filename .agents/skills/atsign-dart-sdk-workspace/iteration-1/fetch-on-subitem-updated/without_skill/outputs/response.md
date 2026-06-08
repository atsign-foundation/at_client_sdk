# Fetching Comment Data on CSubItemUpdated Event

## Overview

When you receive a `CSubItemUpdated` event in response to a comment being added, the event itself typically carries metadata about what changed (such as the key and metadata of the updated record), but not the full comment content. To retrieve the actual comment data, you need to perform an explicit lookup using the atClient API.

## General Approach

The `CSubItemUpdated` event is part of the atProtocol change notification system. When a subscriber receives this event, it indicates that a sub-item (such as a shared record or comment) has been updated. The event payload usually contains:

- The key of the updated record
- Metadata about the change (e.g., `updateType`, timestamps)
- Possibly the `value` field if the notification was sent with `shouldEncrypt` or value-carrying options enabled

However, the value is not always included in the notification itself. In many cases, you must call `get` on the key to fetch the current value.

## Steps to Fetch the Comment Data

### 1. Listen for the Notification

```dart
atClient.notificationService
    .subscribe(regex: 'comment')
    .listen((AtNotification notification) {
  if (notification.type == NotificationType.received) {
    _handleCommentNotification(notification);
  }
});
```

### 2. Extract the Key from the Notification

The notification object contains an `id`, `key`, `from`, `to`, and optionally a `value`. Extract the key so you can do a lookup:

```dart
void _handleCommentNotification(AtNotification notification) async {
  final notificationKey = notification.key;
  // notificationKey might look like: 'comment.somenamespace@alice'
  // or a shared key: '@bob:comment.somenamespace@alice'
  await _fetchCommentData(notificationKey, notification.from);
}
```

### 3. Perform a Lookup Using atClient.get()

Use `atClient.get()` with an `AtKey` constructed from the notification key to retrieve the actual comment content:

```dart
Future<void> _fetchCommentData(String keyStr, String fromAtSign) async {
  try {
    final atKey = AtKey.fromString(keyStr);

    final atValue = await atClient.get(
      atKey,
      getRequestOptions: GetRequestOptions()..bypassCache = true,
    );

    final commentContent = atValue.value;
    print('Comment content: $commentContent');
  } catch (e) {
    print('Error fetching comment: $e');
  }
}
```

Setting `bypassCache = true` ensures you get the latest value from the remote atServer rather than a potentially stale cached copy.

### 4. Alternatively, Check notification.value First

If the sender included the value in the notification (which happens when `NotificationParams` is used with a `value` set), you can read it directly without a round-trip:

```dart
void _handleCommentNotification(AtNotification notification) {
  if (notification.value != null && notification.value!.isNotEmpty) {
    // Value was included in the notification
    print('Comment (from notification): ${notification.value}');
  } else {
    // Need to fetch it explicitly
    _fetchCommentData(notification.key, notification.from);
  }
}
```

## Key Points

- `CSubItemUpdated` / `NotificationType.received` events signal that data changed, but do not always carry the payload.
- Use `atClient.get(AtKey.fromString(notification.key))` to retrieve the current value.
- Use `bypassCache: true` in `GetRequestOptions` to avoid stale cache hits.
- If the key is a shared key (e.g., `@bob:comment@alice`), ensure your atClient is authenticated as the recipient (`@bob`) so it has permission to decrypt and read the value.
- The value stored may be a JSON string if structured comment data is used — deserialize accordingly after fetching.

## Example: Full Handler

```dart
atClient.notificationService
    .subscribe(regex: r'\.comment\.')
    .listen((AtNotification notification) async {
  final key = notification.key;
  final value = notification.value;

  if (value != null && value.isNotEmpty) {
    // Value delivered inline with the notification
    final comment = jsonDecode(value);
    print('New comment: $comment');
  } else {
    // Fetch from atServer
    try {
      final atKey = AtKey.fromString(key);
      final result = await atClient.get(
        atKey,
        getRequestOptions: GetRequestOptions()..bypassCache = true,
      );
      if (result.value != null) {
        final comment = jsonDecode(result.value!);
        print('New comment: $comment');
      }
    } catch (e) {
      print('Failed to fetch comment for key $key: $e');
    }
  }
});
```

## Summary

| Scenario | Action |
|---|---|
| `notification.value` is non-null | Use it directly |
| `notification.value` is null or empty | Call `atClient.get(AtKey.fromString(notification.key))` |
| Want guaranteed fresh data | Always call `atClient.get()` with `bypassCache = true` |

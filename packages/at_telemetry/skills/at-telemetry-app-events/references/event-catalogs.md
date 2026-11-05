# Event catalogs by kind of app

Each catalog is the complete list of what one kind of app sends. Copy the
shape, not the names: use your own app's prefix and words.

In every table, **Peer** is the attribute that names the other endpoint's
atSign, and **Links** is what goes in `notificationIds` or `keys`.

## Remote-controlled device: `acme_gate`

Door controllers that a front desk app unlocks by notification. Full code in
[acme-gate-example.md](acme-gate-example.md).

| Event | Severity | Peer | Other attributes | Links |
| --- | --- | --- | --- | --- |
| `acme_gate.door.unlocked` | info | `acme_gate.command.from` | `acme_gate.door.id`, `acme_gate.unlock.duration_ms` | the command's notification id |
| `acme_gate.door.refused` | warn | `acme_gate.command.from` | `acme_gate.door.id`, `acme_gate.refused.reason` | the command's notification id |
| `acme_gate.door.recovered` | info | | `acme_gate.door.id`, `acme_gate.door.failed_commands` | |
| `acme_gate.desk.recovered` | info | `acme_gate.desk` | `acme_gate.desk.unanswered_updates` | |

| Anomaly event | `anomaly.kind` | Fires when | `anomaly.message` |
| --- | --- | --- | --- |
| `acme_gate.door.failed` | `device_fault` | the first command a door fails to carry out | The lobby door did not open when @front_desk unlocked it. Check the door motor and its power. |
| `acme_gate.desk.unresponsive` | `peer_unresponsive` | the 3rd status update in a row the desk does not answer | @front_desk has not answered the last 3 door status updates. Check that the front desk app is running. |

Does **not** send: one event per status update, or per command received.

## Sensor reporting to a hub: `coldchain`

Fridge sensors (`@fridge_07`) send a reading to a hub (`@coldchain_hub`)
every minute. The hub acknowledges each reading at the app level.

| Event | Severity | Peer | Other attributes | Links |
| --- | --- | --- | --- | --- |
| `coldchain.sensor.calibrated` | info | `coldchain.calibrated.by` | `coldchain.sensor.id`, `coldchain.offset_celsius` | the calibration command's notification id |
| `coldchain.temperature.out_of_range` | warn | `coldchain.reading.hub` | `coldchain.sensor.id`, `coldchain.temperature_celsius`, `coldchain.limit_celsius` | the reading's notification id |
| `coldchain.temperature.back_in_range` | info | `coldchain.reading.hub` | `coldchain.sensor.id`, `coldchain.out_of_range_minutes` | the reading's notification id |
| `coldchain.sensor.recovered` | info | | `coldchain.sensor.id`, `coldchain.missed_readings` | |
| `coldchain.hub.recovered` | info | `coldchain.reading.hub` | `coldchain.unacknowledged_readings` | |

| Anomaly event | `anomaly.kind` | Fires when | `anomaly.message` |
| --- | --- | --- | --- |
| `coldchain.sensor.failed` | `device_fault` | a probe returns no value 3 times in a row | Probe 2 on @fridge_07 has returned no temperature for 3 minutes. Check the probe cable. |
| `coldchain.hub.unresponsive` | `peer_unresponsive` | 15 minutes of readings without an acknowledgement | @coldchain_hub has not acknowledged readings from @fridge_07 for 15 minutes. Check that the hub app is running. |

A fridge that is too warm is a **warn**, not an anomaly: the sensor is working
and the app already alerts its own users. Does **not** send: one event per
reading.

## Chat app: `chat`

People chat between app installs (`@alice`, `@bob`), one APKAM enrollment per
device.

| Event | Severity | Peer | Other attributes | Links |
| --- | --- | --- | --- | --- |
| `chat.conversation.started` | info | `chat.peer` | | the first message's notification id |
| `chat.attachment.shared` | info | `chat.peer` | `chat.attachment.type`, `chat.attachment.bytes` | the message's notification id |
| `chat.attachment.rejected` | warn | `chat.peer` | `chat.attachment.bytes`, `chat.rejected.reason` | |
| `chat.storage.recovered` | info | | `chat.unsaved_attachments` | |

| Anomaly event | `anomaly.kind` | Fires when | `anomaly.message` |
| --- | --- | --- | --- |
| `chat.storage.full` | `storage_full` | the first attachment that cannot be saved | This device is out of space, so received attachments are not being saved. Free up space on the device. |

Does **not** send: one event per message sent or received, message text,
attachment names, or the people in a conversation beyond the peer's atSign.

## Backup agent and vault: `backup`

Laptops (`@laptop_12`) back up to a vault endpoint (`@backup_vault`) every
night. The vault notices a laptop that has gone quiet, because a stopped
agent cannot report itself.

Sent by the laptop:

| Event | Severity | Peer | Other attributes | Links |
| --- | --- | --- | --- | --- |
| `backup.snapshot.completed` | info | `backup.vault` | `backup.files_count`, `backup.bytes`, `backup.duration_ms` | the keys the snapshot wrote |
| `backup.file.skipped` | warn | | `backup.skipped.reason`, `backup.skipped_count` | |

Sent by the vault:

| Event | Severity | Peer | Other attributes | Links |
| --- | --- | --- | --- | --- |
| `backup.source.recovered` | info | `backup.source` | `backup.overdue_hours` | |

| Anomaly event | Sent by | `anomaly.kind` | Fires when | `anomaly.message` |
| --- | --- | --- | --- | --- |
| `backup.vault.full` | laptop | `storage_full` | the first snapshot the vault refuses for space | @backup_vault has no space left for @laptop_12's backup. Add storage or remove old snapshots. |
| `backup.source.overdue` | vault | `overdue` | 26 hours after the last completed snapshot | No backup from @laptop_12 has completed in 26 hours. Check that the laptop is on and the backup agent is running. |

`backup.file.skipped` is sent once per snapshot with a count, not once per
file. Does **not** send: file names or paths, or one event per file.

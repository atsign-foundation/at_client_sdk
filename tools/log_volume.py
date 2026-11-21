#!/usr/bin/env python3
"""Measures the volume and the sync activity in an at_client test-pack log.

Works on a local `./runLocal.sh > run.log 2>&1` capture and on a CI job log
fetched with `gh api /repos/<org>/<repo>/actions/jobs/<job-id>/logs`.

    log_volume.py tally <log> [--top N]     records by level, logger and message shape
    log_volume.py sync <log> [--mode ci|local]  sync rounds, fresh-store pulls, per test file
    log_volume.py levels <log>...           what a proposed set of level moves leaves visible

Each log record is `LEVEL|timestamp|logger|message` (at_utils's console handler).
A CI log prefixes every line with the runner's timestamp, which is stripped.
The CI reporter prints `##[group]✅ test/x.dart: name` when a test COMPLETES,
so a CI line belongs to the next header after it; the local reporter prints
`MM:SS +N: test/x.dart: name` when a test STARTS, so a local line belongs to
the last header before it. `--mode` defaults from the file's content.
"""
import collections
import datetime
import re
import statistics
import sys

LEVELS = ['SHOUT', 'SEVERE', 'WARNING', 'INFO', 'CONFIG', 'FINE', 'FINER', 'FINEST']
RECORD = re.compile(
    r'^(SHOUT|SEVERE|WARNING|INFO|CONFIG|FINE|FINER|FINEST)\|([^|]*)\|([^|]*)\|(.*)$')
CI_PREFIX = re.compile(r'^﻿?\d{4}-\d\d-\d\dT[\d:.]+Z ?')
CI_HEADER = re.compile(r'^##\[group\][^\s]*\s*(test/[^:]+\.dart)')
LOCAL_HEADER = re.compile(r'^\d+:\d+ \+\d+(?: -\d+)?(?: ~\d+)?: (test/[^:]+\.dart)')
COMMIT_IDS = re.compile(
    r'server commit id: (-?\d+) lastReceivedServerCommitId: (-?\d+) pending push count: (\d+)')
RECEIVED = re.compile(r'Received (\d+) from server')
STATS = re.compile(r'RCVD: stats notification in sync: (\d+)')


def shape(message):
    m = message.strip()
    m = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', m)
    m = re.sub(r'\b[0-9a-f]{12,}\b', '<hex>', m)
    m = re.sub(r'@[^\s|:,)\]"\']+', '@A', m)
    m = re.sub(r'\d{4}-\d\d-\d\d[ T][\d:.]+Z?', '<ts>', m)
    m = re.sub(r'\d+', '<n>', m)
    return m[:110]


def logger_shape(name):
    return re.sub(r'@[^\s|:,)\]]+', '@A', name.strip())


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return [CI_PREFIX.sub('', line.rstrip('\n')) for line in f]


def attribute(lines, mode):
    """The test file each line belongs to, by the reporter's convention."""
    owner = [None] * len(lines)
    if mode == 'local':
        current = '(before any test)'
        for i, line in enumerate(lines):
            m = LOCAL_HEADER.match(line)
            if m:
                current = m.group(1)
            owner[i] = current
    else:
        current = '(after the last test)'
        for i in range(len(lines) - 1, -1, -1):
            m = CI_HEADER.match(lines[i])
            if m:
                current = m.group(1)
            owner[i] = current
    return owner


def detect_mode(lines):
    return 'ci' if any(CI_HEADER.match(l) for l in lines) else 'local'


def tally(path, top):
    lines = read(path)
    total = len(lines)
    empty = other = 0
    by_level = collections.Counter()
    by_logger = collections.defaultdict(collections.Counter)
    by_shape = collections.defaultdict(collections.Counter)
    for line in lines:
        if not line.strip():
            empty += 1
            continue
        m = RECORD.match(line)
        if not m:
            other += 1
            continue
        level, _, logger, message = m.groups()
        by_level[level] += 1
        by_logger[level][logger_shape(logger)] += 1
        by_shape[level][(logger_shape(logger), shape(message))] += 1
    records = sum(by_level.values())
    print(f'=== {path}')
    print(f'lines={total} empty={empty} records={records} other={other}')
    for level in LEVELS:
        if by_level[level]:
            print(f'  {level:8s} {by_level[level]:7d}  ({100 * by_level[level] / records:5.1f}%)')
    for level in LEVELS:
        if not by_level[level]:
            continue
        print(f'\n--- {level}: loggers')
        for logger, n in by_logger[level].most_common(12):
            print(f'  {n:7d}  {logger}')
        print(f'--- {level}: message shapes')
        for (logger, s), n in by_shape[level].most_common(top):
            print(f'  {n:7d}  [{logger}] {s}')


def sync(path, mode):
    lines = read(path)
    mode = mode or detect_mode(lines)
    owner = attribute(lines, mode)
    header = CI_HEADER if mode == 'ci' else LOCAL_HEADER
    control = next((l for l in lines if header.match(l)), None)
    print(f'=== {path} mode={mode}')
    print(f'positive control, a header line the attribution matched: {control!r}')
    per = collections.defaultdict(collections.Counter)
    gaps, fresh_gap, incremental_gap = [], 0, 0
    fresh = rounds = batches = entries = 0
    first = last = None
    distinct = collections.defaultdict(set)
    pulls = collections.Counter()
    stats_seen = collections.defaultdict(list)
    for i, line in enumerate(lines):
        m = RECORD.match(line)
        if not m:
            continue
        level, ts, logger, message = m.groups()
        c = per[owner[i]]
        c['records'] += 1
        c[level] += 1
        if 'Pulling to local' in message:
            c['pull'] += 1
            key = message.split(': ', 2)[-1].strip()
            s = shape(key)
            pulls[s] += 1
            distinct[s].add(key)
        if 'Initialising Hive persistence' in message:
            c['clients'] += 1
        mm = STATS.search(message)
        if mm:
            c['stats'] += 1
            stats_seen[owner[i]].append((ts[:19], mm.group(1)))
        mm = RECEIVED.search(message)
        if mm:
            batches += 1
            entries += int(mm.group(1))
            c['entries'] += int(mm.group(1))
        mm = COMMIT_IDS.search(message)
        if mm:
            server, received = int(mm.group(1)), int(mm.group(2))
            rounds += 1
            c['rounds'] += 1
            gap = server - received
            gaps.append(gap)
            if received < 0:
                fresh += 1
                c['fresh'] += 1
                fresh_gap += gap
            else:
                incremental_gap += max(gap, 0)
            first = first or (ts, server)
            last = (ts, server)
    print(f'sync rounds={rounds}; from an empty store={fresh} '
          f'(commit-id distance {fresh_gap}); incremental distance={incremental_gap}')
    if gaps:
        print(f'gap median={statistics.median(gaps)} max={max(gaps)}; '
              f'no-op rounds (gap 0)={sum(1 for g in gaps if g == 0)}')
    print(f'server commit id first={first} last={last}')
    print(f'batches received={batches} entries={entries}; '
          f'pull lines={sum(pulls.values())} distinct keys={sum(len(v) for v in distinct.values())}')
    print('\nkey shapes pulled: lines, distinct keys')
    for s, n in pulls.most_common(10):
        print(f'  {n:6d} {len(distinct[s]):5d}  {s}')
    print('\nper test file: records INFO pulls stats rounds fresh entries clients  '
          'max receivers of one stats notification')
    for t, c in sorted(per.items(), key=lambda kv: -kv[1]['records'])[:20]:
        bursts, previous = [], None
        for key in stats_seen.get(t, []):
            if key == previous:
                bursts[-1] += 1
            else:
                bursts.append(1)
                previous = key
        print(f"  {c['records']:7d} {c['INFO']:7d} {c['pull']:6d} {c['stats']:6d} "
              f"{c['rounds']:5d} {c['fresh']:5d} {c['entries']:7d} {c['clients']:3d}  "
              f"{max(bursts) if bursts else 0:3d}  {t}")


# (logger prefix, message prefix, level it would move to)
MOVES = [
    ('SyncService', 'Pulling to local:', 'FINER'),
    ('SyncService', 'RCVD: stats notification in sync', 'FINER'),
    ('SyncService', 'Received ', 'FINER'),
    ('SyncService', 'Returning serverCommitId', 'FINER'),
    ('SyncService', 'server commit id:', 'FINER'),
    ('SyncService', 'Inside syncComplete', 'FINER'),
    ('SyncService', 'server and local are in sync', 'FINER'),
    ('NotificationServiceImpl', 'Received ', 'FINER'),
    ('AtClientSecretSharing', 'Stored secret envelope', 'FINER'),
    ('AtLookup', 'Creating new connection', 'FINER'),
    ('AtLookup', 'New connection created OK', 'FINER'),
    ('OutboundConnectionImpl', 'close(): calling socket.destroy()', 'FINER'),
    ('AtLookup', 'SENDING: monitor', 'FINER'),
    ('AtClientImpl', 'disallowLegacyEncryption is false', 'INFO'),
    ('AtClientImpl', 'AtClient (', 'FINER'),
    ('AtClientManager', 'setCurrentAtSign called', 'FINER'),
    ('AtClientManager', 'setCurrentAtSign complete', 'FINER'),
    ('NotificationServiceImpl', 'startListening(): starting', 'FINER'),
    ('AtClientSecretSharing', 'publishPublicSigningKey: checking', 'FINER'),
    ('AtClientSecretSharing', 'publishPublicSigningKey: have already', 'FINER'),
    ('AtClientSecretSharing', 'No enrollment id; using', 'FINER'),
    ('AtClientEnvelopeSigner', 'No enrollment id; using', 'FINER'),
    ('SigningKeyMinting', 'No enrollment id; using', 'FINER'),
]


def levels(paths):
    for path in paths:
        before, after = collections.Counter(), collections.Counter()
        lines = read(path)
        empty = sum(1 for l in lines if not l.strip())
        for line in lines:
            m = RECORD.match(line)
            if not m:
                continue
            level, _, logger, message = m.groups()
            before[level] += 1
            new = level
            for logger_prefix, message_prefix, to in MOVES:
                if logger.startswith(logger_prefix) and message.startswith(message_prefix):
                    new = to
                    break
            after[new] += 1
        visible = lambda c: sum(c[l] for l in ('SHOUT', 'SEVERE', 'WARNING', 'INFO'))
        print(f'{path}: lines={len(lines)} empty={empty} | '
              f"INFO {before['INFO']} -> {after['INFO']} | "
              f"WARNING {before['WARNING']} -> {after['WARNING']} | "
              f"SHOUT {before['SHOUT']} -> {after['SHOUT']} | "
              f'visible at info {visible(before)} -> {visible(after)}')


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    command, args = argv[1], argv[2:]
    if command == 'tally':
        top = int(args[args.index('--top') + 1]) if '--top' in args else 30
        tally(args[0], top)
    elif command == 'sync':
        mode = args[args.index('--mode') + 1] if '--mode' in args else None
        sync(args[0], mode)
    elif command == 'levels':
        levels(args)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

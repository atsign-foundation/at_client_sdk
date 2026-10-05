#!/usr/bin/env python3
"""Holds an exclusive lock on a key for a process, until that process exits or this one is killed.

  hold_lock.py <key> <owner-pid>

Prints "locked" on stdout once the lock is held, after waiting (and saying so on stderr) while
another process holds it. The lock is the kernel's, so it is released when this process exits
however it exits; it exits once the owner has, including while still waiting.
"""
import fcntl
import os
import re
import subprocess
import sys
import time

LOCK_DIR = "/tmp/atsign-rig-locks"


def lock_file(key):
    kind, _, rest = key.partition(":")
    if rest.startswith("/"):
        rest = os.path.realpath(rest)
    return os.path.join(LOCK_DIR, re.sub(r"[^A-Za-z0-9._-]", "_", f"{kind}:{rest}") + ".lock")


def describe(pid):
    cmd = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return f"pid {pid} ({cmd[:160]})"


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def try_lock(f):
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except BlockingIOError:
        return False


def main():
    key, owner = sys.argv[1], int(sys.argv[2])
    os.makedirs(LOCK_DIR, exist_ok=True)
    f = open(lock_file(key), "a+")
    if not try_lock(f):
        f.seek(0)
        holder = f.read().split()
        print(f"==> waiting for {key}, held by {describe(int(holder[0])) if holder else 'another run'}",
              file=sys.stderr, flush=True)
        # NOTE polled rather than blocking, so a waiter whose owner was interrupted gives up its
        # place instead of taking the lock for a run that no longer exists.
        while not try_lock(f):
            if not alive(owner):
                return
            time.sleep(0.5)
    f.seek(0)
    f.truncate()
    f.write(f"{owner}\n")
    f.flush()
    print("locked", flush=True)
    sys.stdout.close()
    while alive(owner):
        time.sleep(0.5)


if __name__ == "__main__":
    main()

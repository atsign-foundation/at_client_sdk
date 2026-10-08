This directory contains the golden envelope `envelope_v1_golden.json` (v1 format).
It is sealed under a PrfSecret of bytes 0..31 and a PassphraseSecret('golden-passphrase-not-secret').
Any envelope writer (e.g. the portal) must produce envelopes that our reader opens exactly as demonstrated.
This file is a contract and is never regenerated unless the envelope format `v` changes.

# Artifact policy

`downloads/` holds locally downloaded recovery, stock-ROM and later build-input
binaries.  `device-private/` holds device-bound backups such as modem NV and
calibration partitions.

Both directories are intentionally ignored by Git:

- third-party binary files should not be mirrored unintentionally;
- device-private images may contain serialised identity, radio calibration,
  fingerprint/sensor calibration or other sensitive material.

Every accepted binary must instead have a tracked manifest containing its
source URL, expected and observed hashes, size, acquisition date and validation
status.  Device-private files additionally require mode `0600`; their parent
directory is mode `0700`.  `userdata` is explicitly excluded from backup at the
user's request.

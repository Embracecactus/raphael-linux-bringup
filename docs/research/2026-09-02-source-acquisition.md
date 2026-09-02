# Raphael source acquisition and mirror verification

Date: 2026-09-02, Asia/Shanghai

## Outcome

No public Gitee or GitCode repository was found for the two exact Gavin Liu
Raphael repositories.  Public GitHub accelerators were therefore treated only
as untrusted transports.  Source acceptance did not depend on an accelerator's
name, TLS endpoint or archive filename: every imported archive was reconstructed
as a Git tree and compared with the tree object ID returned independently by
GitHub's official API.

The two source trees required for the first source build are now present under
`third_party/` and have passed that full-content check.

## Mirror and transport probes

- Gitee's public repository search API returned an empty array for
  `xiaomi_raphael_kernel`, `xiaomi_raphael_build_kernel`, `raphael kernel` and
  `GavinLiuOnline`.
- Common GitCode `gh_mirrors/xia/...` and `gh_mirrors/xr/...` Git paths returned
  HTTP 403 with `The project you were looking for could not be found`.
- `ghfast.top`, recommended as a domestic accelerator by the community image
  project, failed one Git TLS handshake and another probe did not complete in
  30 seconds on this host.
- Both `gh.xmly.dev` and `gh-proxy.com` returned the exact expected Git refs.
  Their single-stream shallow clones were still slow, so they were not used for
  the final transfer.
- A 1 MiB archive probe through `gh.ddlc.top` transferred about 545 KiB/s.  It
  was used only to transport commit-addressed GitHub archives.  Git smart HTTP
  on the same endpoint was not accepted and was not part of the trust chain.

Relevant service documentation and project context:

- GitCode repository mirroring:
  https://docs.gitcode.com/docs/help/home/org_project/project_manage/project_settings/repository_mirroring/
- Community Raphael image project and its domestic-acceleration note:
  https://github.com/GengWei1997/linux-xiaomi-raphael-uboot

## Accepted inputs

| Input | Commit | Official Git tree | Archive bytes | Archive SHA-256 |
| --- | --- | --- | ---: | --- |
| Kernel build/config repository | `128ac1fec88e7a141cebfab4193c6c4cc512a1d1` | `ee3e9a20ba8b20b438ff649e4ced707d54611bb1` | 75,400,361 | `606e5b33afa19d234067557758de6f713879a0df9442af9b36ef0bdcb1349c99` |
| Kernel release baseline | `c526b7bf7ebc3fbfee244be252a2c1bd061ca749` | `505b5c0cbd9307ce58f62a8d48150a49217735f6` | 260,658,408 | `d18e0ae1a9a76d467a5daf8c5e7d2265b3edfbddafe3e2752f51dffc852c66ba` |

`tools/raphael/import_verified_github_archive.sh` performed these checks before
placing either tree under `third_party/`:

1. validate gzip integrity and a single exact top-level directory;
2. reject member traversal, special files and symlinks escaping the tree;
3. build a fresh external Git object database from every file, executable bit
   and symlink, ignoring `.gitignore`;
4. require `git write-tree` to equal the official tree object ID.

`tools/raphael/verify_git_tree.sh` repeats the fourth check on the unpacked tree
before each build, so later local drift cannot silently enter an artifact.

## Why the first build uses `c526b7bf`, not today's branch head

The current `raphael-7.0` branch head was independently observed as
`a35058bc6508db6091c1563022d59825516a0567`, five commits ahead of
`c526b7bf7ebc3fbfee244be252a2c1bd061ca749`.  Those later commits incorporate
the older external patch stack and add charging-related work.

The published `kernel-v7.0` package, however, records
`7.0.0-sm8150-gc526b7bf7ebc-dirty` in its embedded configuration.  In addition,
the first blob index in the exact build-repository patch matches the Raphael
DTS blob at `c526b7bf`.  `git apply --check` also passes cleanly only on this
release baseline.  This establishes the original build relationship:

`c526b7bf source + 128ac1fe build config/patch -> published v7.0 lineage`

The first hardware boot therefore uses that reconstructable lineage.  The
newer `a35058bc` branch remains recorded in `third_party/SOURCES.lock` for a
post-boot update review; it is not being conflated with the published binary.

## Incomplete transfers retained as evidence

Slow direct downloads and the superseded current-head download were stopped,
not consumed.  Their filenames end in `.partial`:

| Partial input | Bytes at stop |
| --- | ---: |
| Direct build-repository archive | 9,095,851 |
| Direct current-head kernel archive | 8,921,367 |
| Accelerated current-head kernel archive | 83,136,512 |

They are outside Git under `artifacts/downloads/source/` and cannot be mistaken
for accepted `.tar.gz` inputs.

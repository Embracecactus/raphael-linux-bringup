#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Archive boundary and no-overwrite regression tests; no network or devices."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / 'fetch_boot_inputs.py'
spec = importlib.util.spec_from_file_location('fetch_boot_inputs', TOOL)
fetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch)


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.payload = {n: ('fixture:' + n).encode() for n in fetch.REQUIRED}
        self.lock = {n: {'bytes': len(b), 'sha256': hashlib.sha256(b).hexdigest()} for n, b in self.payload.items()}
        (self.root / 'config/raphael').mkdir(parents=True)
        (self.root / 'tools/raphael').mkdir(parents=True)
        shutil.copyfile(TOOL, self.root / 'tools/raphael/fetch_boot_inputs.py')
        (self.root / 'config/raphael/boot-inputs.lock.json').write_text(json.dumps(self.lock))
        self.target = self.root / 'artifacts/retained/raphael-boot-inputs'

    def archive(self, extra=None, omit=(), bad_content=False):
        path = self.root / 'inputs.tar.gz'
        with tarfile.open(path, 'w:gz', format=tarfile.USTAR_FORMAT) as bundle:
            for name, body in self.payload.items():
                if name in omit:
                    continue
                member = tarfile.TarInfo(name)
                member.size = len(body)
                bundle.addfile(member, io.BytesIO(b'X' * len(body) if bad_content else body))
            if extra is not None:
                bundle.addfile(extra, io.BytesIO(b'X' * extra.size))
        record = {'name': path.name, 'bytes': path.stat().st_size,
                  'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                  'url': f'https://github.com/{fetch.REPOSITORY}/releases/download/test-v1/{path.name}',
                  'inputs': list(fetch.REQUIRED)}
        (self.root / 'config/raphael/boot-inputs.release.json').write_text(json.dumps({
            'repository': fetch.REPOSITORY, 'tag': 'test-v1',
            'lock_file': 'config/raphael/boot-inputs.lock.json', 'archive': record}))
        return path

    def run_fetch(self, *args):
        return subprocess.run(['python3', str(self.root / 'tools/raphael/fetch_boot_inputs.py'),
                               *map(str, args)], capture_output=True, text=True)

    def test_valid_install_and_repeat(self):
        archive = self.archive()
        for _ in range(2):
            result = self.run_fetch('--archive', archive)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.run_fetch('--check').returncode, 0)
        for n, data in self.payload.items():
            self.assertEqual((self.target / n).read_bytes(), data)

    def test_existing_mismatch_preserved(self):
        archive = self.archive()
        self.target.mkdir(parents=True)
        path = self.target / fetch.REQUIRED[0]
        path.write_bytes(b'keep-user-data')
        self.assertNotEqual(self.run_fetch('--archive', archive).returncode, 0)
        self.assertEqual(path.read_bytes(), b'keep-user-data')
        self.assertEqual(len(list(self.target.iterdir())), 1)

    def test_archive_hash_rejected_before_install(self):
        archive = self.archive()
        archive.write_bytes(archive.read_bytes()[:-1] + b'X')
        self.assertNotEqual(self.run_fetch('--archive', archive).returncode, 0)
        self.assertFalse(self.target.exists())

    def test_unsafe_members(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/absolute', tarfile.REGTYPE),
                           ('extra', tarfile.REGTYPE), ('directory', tarfile.DIRTYPE),
                           (fetch.REQUIRED[0], tarfile.SYMTYPE), (fetch.REQUIRED[0], tarfile.LNKTYPE),
                           (fetch.REQUIRED[0], tarfile.FIFOTYPE), (fetch.REQUIRED[0], tarfile.REGTYPE)]:
            with self.subTest(name=name, kind=kind):
                member = tarfile.TarInfo(name)
                member.type = kind
                member.linkname = '../escape' if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ''
                omit = (name,) if kind != tarfile.REGTYPE and name in fetch.REQUIRED else ()
                archive = self.archive(extra=member, omit=omit)
                self.assertNotEqual(self.run_fetch('--archive', archive).returncode, 0)
                self.assertFalse(self.target.exists())
        self.assertFalse((self.root.parent / 'escape').exists())

    def test_member_hash_and_missing(self):
        for options in ({'bad_content': True}, {'omit': (fetch.REQUIRED[0],)}):
            archive = self.archive(**options)
            self.assertNotEqual(self.run_fetch('--archive', archive).returncode, 0)
            self.assertFalse(self.target.exists())

    def test_destination_symlink_rejected(self):
        archive = self.archive()
        self.target.parent.mkdir(parents=True)
        elsewhere = self.root / 'elsewhere'
        elsewhere.mkdir()
        self.target.symlink_to(elsewhere, target_is_directory=True)
        self.assertNotEqual(self.run_fetch('--archive', archive).returncode, 0)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_partial_release_requires_original(self):
        missing = fetch.REQUIRED[0]
        archive = self.archive(omit=(missing,))
        manifest = self.root / 'config/raphael/boot-inputs.release.json'
        release = json.loads(manifest.read_text())
        release['archive']['inputs'].remove(missing)
        manifest.write_text(json.dumps(release))
        self.assertNotEqual(self.run_fetch('--archive', archive).returncode, 0)
        self.assertFalse(self.target.exists())
        saved = self.root / 'downloaded.tar.gz'
        self.assertEqual(self.run_fetch('--archive', archive, '--download-only', saved).returncode, 0)
        self.assertFalse(self.target.exists())
        local = self.root / 'own-originals'
        local.mkdir()
        (local / missing).write_bytes(self.payload[missing])
        result = self.run_fetch('--archive', archive, '--local-input-dir', local)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()

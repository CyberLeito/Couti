"""Verify that binary localization changed only the recorded diagnostic bytes."""
import hashlib
import json
import lzma
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LegacyBsdTests(unittest.TestCase):
    def test_payload_changes_are_limited_to_recorded_strings(self):
        manifest = json.loads((ROOT / 'tools/build/legacy-bsd-branding.json').read_text())
        self.assertEqual(len(manifest), 20)
        for entry in manifest:
            with self.subTest(path=entry['path']):
                path = ROOT / entry['path']
                data = path.read_bytes()
                if path.suffix == '.xz':
                    data = lzma.decompress(data)
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry['branded_elf_sha256'])
                original = bytearray(data)
                for change in entry['changes']:
                    offset = change['offset']
                    before, after = change['old'].encode(), change['new'].encode()
                    self.assertEqual(len(before), len(after))
                    self.assertEqual(data[offset:offset + len(after)], after)
                    original[offset:offset + len(before)] = before
                self.assertEqual(hashlib.sha256(original).hexdigest(), entry['original_elf_sha256'])
                if 'branded_filesystem_sha256' in entry:
                    image = lzma.decompress((ROOT / 'INSTALL/ventoy/dragonfly.mfs.xz').read_bytes())
                    self.assertEqual(hashlib.sha256(image).hexdigest(), entry['branded_filesystem_sha256'])
                    original = bytearray(image)
                    for change in entry['changes']:
                        offset = change['filesystem_offset']
                        before, after = change['old'].encode(), change['new'].encode()
                        self.assertEqual(image[offset:offset + len(after)], after)
                        original[offset:offset + len(before)] = before
                    self.assertEqual(hashlib.sha256(original).hexdigest(), entry['original_filesystem_sha256'])

import importlib.util
import lzma
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    'branding', Path(__file__).resolve().parents[1] / 'check_boot_branding.py')
branding = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(branding)


def cpio_member(name, data):
    filename = name.encode() + b'\0'
    fields = [0, 0o100644, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(filename), 0]
    header = b'070701' + b''.join(('%08x' % value).encode() for value in fields)
    result = header + filename
    result += b'\0' * (-len(result) % 4)
    result += data
    return result + b'\0' * (-len(result) % 4)


class BootBrandingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('EFI', 'ventoy', 'grub'):
            (self.root / folder).mkdir()

    def test_rejects_old_ascii_and_utf16_firmware_messages(self):
        for encoding in ('ascii', 'utf-16-le'):
            with self.subTest(encoding=encoding):
                (self.root / 'EFI/loader.efi').write_bytes(
                    'This is NOT a standard Ventoy device'.encode(encoding))
                self.assertTrue(branding.artifact_errors(self.root))

    def test_accepts_couti_and_preserves_internal_interfaces(self):
        (self.root / 'EFI/loader.efi').write_bytes(
            b'Couti scanning files\0/ventoy/ventoy.json\0VentoyOsParam\0'
            b'VENTOY COMPATIBLE\0Copyright longpanda <admin@ventoy.net>\0')
        self.assertEqual(branding.artifact_errors(self.root), [])

    def test_detects_nested_compressed_initramfs_message(self):
        inner = cpio_member('init', b'echo "VENTOY DEBUG"\n')
        inner += cpio_member('TRAILER!!!', b'')
        outer = cpio_member('hook.cpio.xz', lzma.compress(inner))
        outer += cpio_member('TRAILER!!!', b'')
        (self.root / 'ventoy/boot.cpio').write_bytes(outer)
        errors = branding.artifact_errors(self.root)
        self.assertTrue(any('hook.cpio.xz:xz:init' in error for error in errors))

    def test_rejects_upstream_enrollment_certificate(self):
        (self.root / 'enroll.cer').write_bytes(b'certificate subject Ventoy')
        self.assertTrue(branding.artifact_errors(self.root))

    def test_rejects_upstream_authenticode_certificate(self):
        image = bytearray(512)
        image[:2] = b'MZ'
        struct.pack_into('<I', image, 60, 64)
        image[64:68] = b'PE\0\0'
        struct.pack_into('<H', image, 88, 0x20b)
        cert = b'certificate issuer Ventoy'
        struct.pack_into('<II', image, 64 + 24 + 112 + 32, 512, len(cert))
        (self.root / 'EFI/loader.efi').write_bytes(image + cert)
        self.assertTrue(any('signing certificate' in error
                            for error in branding.artifact_errors(self.root)))

    def test_rejects_malformed_archive(self):
        broken = cpio_member('init', b'x')[:-4]
        with self.assertRaises(ValueError):
            list(branding.payloads('broken.cpio', broken))

    def test_missing_boot_partition_is_not_a_pass(self):
        self.assertTrue(branding.artifact_errors(self.root / 'missing'))

    def test_iso_label_machine_protocol_is_preserved(self):
        source = (branding.ROOT / 'VtoyTool/vtoydm.c').read_text(encoding='utf-8')
        self.assertIn('printf("VENTOY_ISO_LABEL %s\\n", label)', source)


if __name__ == '__main__':
    unittest.main()

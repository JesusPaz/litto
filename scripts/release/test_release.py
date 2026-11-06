import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import datetime
import hashlib
from version import parse

SCRIPTS = Path(__file__).parent.resolve()


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseTests(unittest.TestCase):
    def test_versions(self):
        self.assertEqual(parse('v0.1.0-rc.1'), ('0.1.0', True))
        self.assertEqual(parse('v1.2.3'), ('1.2.3', False))
        for value in ['1.2.3', 'v01.2.3', 'v1.2.3-rc.0', 'v1.2.3;echo bad', 'v1.2.3\n', 'v10000.0.0']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse(value)

    def test_build_number_grows_and_fits_apple_format(self):
        build = load('build_number', 'build-number.py').build_number
        start = datetime.datetime(2026, 11, 6, tzinfo=datetime.timezone.utc)
        first, later = build(start), build(start + datetime.timedelta(minutes=1))
        self.assertRegex(first, r'^[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}$')
        self.assertGreater(tuple(map(int, later.split('.'))), tuple(map(int, first.split('.'))))

    def test_export_options(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'options.plist'
            subprocess.run([sys.executable, str(SCRIPTS / 'export-options.py'), 'mac', 'export', str(path)], check=True)
            mac = plistlib.loads(path.read_bytes())
            self.assertEqual((mac['method'], mac['destination'], mac['signingStyle']), ('developer-id', 'export', 'automatic'))
            subprocess.run([sys.executable, str(SCRIPTS / 'export-options.py'), 'ios', 'upload', str(path)], check=True)
            ios = plistlib.loads(path.read_bytes())
            self.assertEqual((ios['method'], ios['testFlightInternalTestingOnly']), ('app-store-connect', True))

    def test_expected_mac_assets(self):
        delivery = load('eas_delivery', 'eas-delivery.py')
        self.assertEqual(delivery.expected_assets('v0.1.0-rc.1'),
                         {'Litto-v0.1.0-rc.1-macOS.dmg', 'Litto-v0.1.0-rc.1-macOS.zip', 'SHA256SUMS'})

    def test_cask_tracks_exact_archive_and_channel(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive, cask = Path(tmp) / 'app.zip', Path(tmp) / 'litto.rb'
            archive.write_bytes(b'litto')
            for tag, token, conflict in [('v0.1.0-rc.2', 'litto@preview', 'litto'), ('v0.1.0', 'litto', 'litto@preview')]:
                subprocess.run([sys.executable, str(SCRIPTS / 'cask.py'), tag, str(archive), str(cask)], check=True)
                text = cask.read_text()
                self.assertIn(f'cask "{token}" do', text)
                self.assertIn(f'version "{tag[1:]}"', text)
                self.assertIn('sha256 "' + hashlib.sha256(b'litto').hexdigest() + '"', text)
                self.assertIn(f'conflicts_with cask: "{conflict}"', text)
                self.assertIn('Litto-v#{version}-macOS.zip', text)


if __name__ == '__main__':
    unittest.main()

"""Native GLib launcher checks, run on Linux with python3-gi installed."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'linux/resources'


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bdk-launcher-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.data = self.base / 'user data'
        self.desktop = self.data / 'applications/com.bdkaudio.bdk_audio.desktop'
        self.env = dict(os.environ, XDG_DATA_HOME=str(self.data))

    def bundle(self, name):
        bundle = self.base / name
        bundle.mkdir()
        executable = bundle / 'bdk_audio'
        marker = bundle / 'launch-receipt'
        executable.write_text('#!/bin/sh\nprintf launched > ' + shlex.quote(str(marker)) + '\n')
        executable.chmod(0o755)
        icon = bundle / 'share/icons/hicolor/512x512/apps/com.bdkaudio.bdk_audio.png'
        icon.parent.mkdir(parents=True)
        shutil.copyfile(REPO / 'linux/resources/com.bdkaudio.bdk_audio.png', icon)
        script = SOURCE / 'register-launcher.sh'
        shutil.copyfile(script, bundle / script.name)
        return bundle

    def register(self, bundle):
        script = bundle / 'register-launcher.sh'
        return subprocess.run(['bash', str(script)], env=self.env, capture_output=True, text=True)

    def launch(self, bundle):
        result = self.register(bundle)
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            app = Gio.DesktopAppInfo.new_from_filename(str(self.desktop))
        except TypeError:
            self.fail('Desktop launcher cannot resolve the extracted bundle executable:\n' + self.desktop.read_text())
        self.assertIsNotNone(app)
        self.assertTrue(app.launch([], None))
        self.assertEqual(app.get_icon().get_file().get_path(), str(bundle / 'share/icons/hicolor/512x512/apps/com.bdkaudio.bdk_audio.png'))
        marker = bundle / 'launch-receipt'
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertEqual(marker.read_text(), 'launched')

    def test_extracted_bundle_launches_outside_path(self):
        self.launch(self.bundle('BDK Audio'))

    def test_reserved_characters_remain_literal(self):
        for name in ['BDK "quotes"', 'BDK $cash', 'BDK `tick`', 'BDK %percent', 'BDK \\slash', 'BDK "quotes" $cash `tick` %percent \\slash']:
            with self.subTest(name=name):
                self.launch(self.bundle(name))

    def test_registering_moved_bundle_updates_the_launch_target(self):
        bundle = self.bundle('before move')
        self.launch(bundle)
        (bundle / 'launch-receipt').unlink()
        moved = self.base / 'after move'
        bundle.rename(moved)
        # Rewrite only the stub's receipt destination after the move.
        (moved / 'bdk_audio').write_text('#!/bin/sh\nprintf launched > ' + shlex.quote(str(moved / 'launch-receipt')) + '\n')
        self.launch(moved)

    def test_invalid_bundle_preserves_an_existing_launcher(self):
        bundle = self.bundle('valid')
        self.launch(bundle)
        before = self.desktop.read_bytes()
        (bundle / 'bdk_audio').unlink()
        result = self.register(bundle)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.desktop.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()

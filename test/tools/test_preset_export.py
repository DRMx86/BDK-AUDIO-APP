import importlib.util
import json
from pathlib import Path
import unittest

source = Path(__file__).resolve().parents[2] / 'tools/export_android_presets.py'
spec = importlib.util.spec_from_file_location('preset_export', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ExportTest(unittest.TestCase):
    def test_only_custom_preset_fields_leave_the_original_preferences(self):
        result = json.loads(module.curate(b'''<map>
<string name="device_address">private value</string>
<string name="custom_preset_1_name">Night &amp; day</string>
<int name="custom_preset_1_bass" value="80"/>
<int name="custom_3_bass" value="25"/>
</map>'''))
        self.assertEqual(result['preferences'], {
            'custom_preset_1_name': 'Night & day', 'custom_preset_1_bass': 80,
            'custom_3_bass': 25})
        self.assertEqual(result['format'], 'bdk-android-prefs')

    def test_invalid_entries_never_create_a_partial_backup(self):
        for raw in [b'<map><int name="custom_1_bass" value="101"/></map>',
                    b'<map><string name="custom_1_bass">50</string></map>',
                    b'<map><int name="custom_1_bass" value="50"/><int name="custom_1_bass" value="60"/></map>',
                    b'<!DOCTYPE map [<!ENTITY x "bad">]><map/>',
                    b'x' * (module.MAXIMUM_BYTES + 1)]:
            with self.subTest(raw=raw[:40]), self.assertRaises(ValueError):
                module.curate(raw)


if __name__ == '__main__':
    unittest.main()

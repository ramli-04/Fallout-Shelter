import pathlib
import sys
import unittest


class ProjectTests(unittest.TestCase):
    def test_supported_python(self):
        self.assertGreaterEqual(sys.version_info[:2], (3, 11))

    def test_standard_library_baseline(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        self.assertTrue((root / "requirements.txt").exists())
        self.assertTrue((root / "models" / "__init__.py").exists())
        self.assertTrue((root / "simulation" / "__init__.py").exists())

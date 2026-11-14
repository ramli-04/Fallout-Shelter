import json
import tempfile
import unittest
from pathlib import Path
from tools.survival_report import render


class SurvivalReportTests(unittest.TestCase):
    def test_charts_keep_missing_data_and_escape_report(self):
        shelters = {f'S{i}': dict(exists=i != 5, occupancy=i, food_person_days=10*i,
                    water_liters=20*i, survival_rate=None if i == 5 else i/5,
                    family_survivors=i, infrastructure_reliability=None if i == 5 else .9,
                    stress=[] if i == 5 else [i*10]) for i in range(1, 6)}
        data = dict(samples=[dict(day=d, shelters=shelters) for d in (0, 5, 10)],
                    shelters=shelters, population={'label': '<script>alert(1)</script>'},
                    family={}, social={}, initial_social={}, storyteller={}, ai={},
                    survivor_outcomes={}, daily_reports=[])
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'results.json'
            source.write_text(json.dumps(data), encoding='utf-8')
            output = render(source)
            self.assertEqual(len(list(Path(folder).glob('*.png'))), 7)
            self.assertEqual(len(list(Path(folder).glob('*.svg'))), 7)
            self.assertTrue(all(p.stat().st_size > 1000 for p in Path(folder).glob('*.png')))
            page = output.read_text(encoding='utf-8')
            self.assertNotIn('<script>', page)
            self.assertIn('&lt;script&gt;', page)
            self.assertIn('Missing observations remain gaps', page)
            self.assertEqual(json.loads(source.read_text()), data)

    def test_recorded_ten_day_run_exports(self):
        path = Path('outputs/survival-test-results.json')
        if not path.exists():
            self.skipTest('Run test_survival_lifecycle.gd to generate the recorded fixture')
        data = json.loads(path.read_text())
        self.assertEqual(len(data['daily_reports']), 10)
        self.assertEqual(data['samples'][0]['day'], 0)
        self.assertEqual(data['samples'][-1]['day'], 10)
        self.assertEqual(set(data['shelters']), {'S1', 'S2', 'S3', 'S4', 'S5'})
        with tempfile.TemporaryDirectory() as folder:
            copied = Path(folder)/'results.json'
            copied.write_text(json.dumps(data), encoding='utf-8')
            self.assertTrue(render(copied).exists())


if __name__ == '__main__':
    unittest.main()

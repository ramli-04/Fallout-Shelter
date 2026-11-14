"""Run with .tools/graphify/venv/Scripts/python.exe -m unittest tests.test_graphify_integration."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

from tools.graphify_essaim import GodotExtractor, read_source


@unittest.skipUnless(importlib.util.find_spec("tree_sitter_language_pack"), "optional Graphify environment required")
class GodotGraphTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_ast_calls_preloads_scenes_and_python_bridge(self):
        math = self.write("scripts/math.gd", "extends RefCounted\nstatic func sum_values():\n\treturn 1\n")
        main = self.write("scripts/main.gd", '''extends Node
const Math = preload("res://scripts/math.gd")
func start():
    run()
    Math.sum_values()
    OS.execute("python", ["-m", "ai_service.server"])
func run():
    pass
''')
        scene = self.write("scenes/main.tscn", '[ext_resource type="Script" path="res://scripts/main.gd" id="1"]')
        python = self.write("ai_service/server.py", "def start(): pass\n")
        native = {"nodes": [{"id": "native_server", "label": "server.py", "source_file": "ai_service/server.py"}]}
        adapter = GodotExtractor(self.root, native)
        result = adapter.extract([main, math, scene])
        edges = {(edge["source"], edge["target"], edge["relation"]): edge for edge in result["edges"]}
        start = "essaim:scripts/main.gd#start"
        self.assertIn((start, "essaim:scripts/main.gd#run", "calls"), edges)
        cross = edges[(start, "essaim:scripts/math.gd#sum_values", "calls")]
        self.assertEqual(cross["confidence"], "INFERRED")
        self.assertEqual(cross["source_location"], "L5")
        self.assertIn(("essaim:scenes/main.tscn", "essaim:scripts/main.gd", "references"), edges)
        self.assertIn((start, "native_server", "references"), edges)
        self.assertFalse(adapter.warnings)

    def test_comments_strings_and_shadowed_aliases_do_not_create_calls(self):
        library = self.write("library.gd", "extends RefCounted\nfunc hit():\n    pass\n")
        main = self.write("main.gd", '''extends Node
const Library = preload("res://library.gd")
# Library.hit() and preload("res://fake.gd") are comments.
func first():
    var text = 'Library.hit() and preload("res://fake.gd")'
func second(Library: Dictionary):
    Library.hit()
func third():
    var Library = {}
    Library.hit()
func fourth():
    Library.hit()
''')
        adapter = GodotExtractor(self.root)
        graph = adapter.extract([main, library])
        calls = [edge for edge in graph["edges"] if edge["relation"] == "calls"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["source"], "essaim:main.gd#fourth")
        self.assertFalse(any("fake.gd" in str(node) for node in graph["nodes"]))

    def test_external_and_sensitive_resources_are_excluded(self):
        self.write(".env", "SECRET=not-for-graph")
        self.write(".tools/third_party.gd", "extends Node")
        self.write("outputs/private.json", "{}")
        adapter = GodotExtractor(self.root)
        for reference in ["res://.env", "res://.tools/third_party.gd", "res://outputs/private.json", "res://../outside.gd"]:
            self.assertIsNone(adapter.resource(reference))

    def test_document_links_and_legacy_encoding(self):
        source = self.write("scripts/car.gd", "extends Node\nfunc drive():\n    pass\n")
        document = self.root / "docs/guide.md"
        document.parent.mkdir()
        document.write_bytes(b"# Vehicles \x97 guide\n[Car](../scripts/car.gd)\n")
        self.assertIn("\u2014", read_source(document))
        graph = GodotExtractor(self.root).extract([source, document])
        self.assertTrue(any(edge["relation"] == "documents" and edge["target"] == "essaim:scripts/car.gd" for edge in graph["edges"]))

    def test_bad_syntax_is_reported_and_rebuilds_do_not_duplicate_nodes(self):
        source = self.write("broken.gd", "extends Node\nfunc valid():\n    pass\nfunc broken(\n")
        adapter = GodotExtractor(self.root)
        first = adapter.extract([source])
        self.assertTrue(adapter.warnings)
        second = GodotExtractor(self.root).extract([source])
        self.assertEqual(first["nodes"], second["nodes"])
        self.assertEqual(len(first["nodes"]), len({node["id"] for node in first["nodes"]}))


if __name__ == "__main__":
    unittest.main()

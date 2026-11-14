"""Build ESSAIM's local Graphify graph, including Godot files unsupported upstream."""
from __future__ import annotations

import ast
from collections import Counter
from importlib.metadata import version
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT_SUFFIXES = {".gd", ".tscn", ".tres", ".godot"}


def read_source(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        # Older project reports were saved by Windows PowerShell in ANSI.
        return path.read_text(encoding="cp1252")


def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)


class GodotExtractor:
    """Read AST declarations/calls and literal resource links; never execute game code."""

    def __init__(self, root: Path, native: dict | None = None):
        self.root = root.resolve()
        self.nodes = {}
        self.edges = {}
        self.modules = {}
        self.functions = {}
        self.parses = {}
        self.warnings = []
        for node in (native or {}).get("nodes", []):
            source = node.get("source_file", "").replace("\\", "/")
            if node.get("label") in {source, Path(source).name}:
                self.modules.setdefault(source, node["id"])

    def relative(self, path: Path) -> str:
        return path.resolve().relative_to(self.root).as_posix()

    def module(self, path: Path) -> str:
        source = self.relative(path)
        if source not in self.modules:
            node_id = "essaim:" + source
            kind = "code" if path.suffix == ".gd" else "document" if path.suffix == ".md" else "config"
            self.nodes[node_id] = {"id": node_id, "label": source, "file_type": kind,
                                   "source_file": source, "source_location": "L1",
                                   "essaim_extractor": "godot-ast-v1"}
            self.modules[source] = node_id
        return self.modules[source]

    def edge(self, source, target, relation, path, line, confidence="EXTRACTED"):
        key = (source, target, relation)
        self.edges.setdefault(key, {"source": source, "target": target, "relation": relation,
                                   "confidence": confidence, "weight": 1.0,
                                   "source_file": self.relative(path), "source_location": f"L{line}"})

    def resource(self, text: str) -> Path | None:
        if not text.startswith("res://"):
            return None
        path = (self.root / text[6:]).resolve()
        if not path.is_relative_to(self.root) or not path.is_file():
            return None
        # Only link to this project's source/config corpus, never dependencies or secrets.
        if any(part.startswith(".") or part in {"outputs", "graphify-out", "assets", "__pycache__"}
               for part in path.relative_to(self.root).parts):
            return None
        return path

    @staticmethod
    def literal(node) -> str | None:
        try:
            value = ast.literal_eval(node.text.decode("utf-8"))
            return value if isinstance(value, str) else None
        except (SyntaxError, ValueError):
            return None

    def declarations(self, path: Path):
        from tree_sitter_language_pack import get_parser
        tree = get_parser("gdscript").parse(read_source(path).encode("utf-8"))
        self.parses[path] = tree
        if tree.root_node.has_error:
            self.warnings.append(f"{self.relative(path)}: grammar reported a parse error; partial AST indexed")
        module = self.module(path)

        def visit(node, owner, prefix=""):
            name_node = node.child_by_field_name("name")
            if node.type in {"function_definition", "class_definition", "signal_statement"} and name_node:
                name = prefix + name_node.text.decode("utf-8")
                node_id = "essaim:" + self.relative(path) + "#" + name
                callable_node = node.type == "function_definition"
                self.nodes[node_id] = {"id": node_id,
                                       "label": f"{path.stem}.{name}" + ("()" if callable_node else ""),
                                       "file_type": "code", "source_file": self.relative(path),
                                       "source_location": f"L{node.start_point.row + 1}",
                                       "essaim_extractor": "godot-ast-v1", "_callable": callable_node}
                self.edge(owner, node_id, "contains", path, node.start_point.row + 1)
                if callable_node:
                    self.functions[(path, name)] = node_id
                owner = node_id
                if node.type == "class_definition":
                    prefix = name + "."
            for child in node.named_children:
                visit(child, owner, prefix)
        visit(tree.root_node, module)

    def relationships(self, path: Path):
        tree = self.parses[path]
        aliases = {}
        module = self.module(path)
        # Lexical scopes keep local preload aliases from leaking between functions.
        def visit(node, owner=module, scope="", class_prefix=""):
            name_node = node.child_by_field_name("name")
            if node.type == "class_definition" and name_node:
                class_prefix += name_node.text.decode("utf-8") + "."
                owner = "essaim:" + self.relative(path) + "#" + class_prefix.rstrip(".")
            if node.type == "function_definition" and name_node:
                scope = class_prefix + name_node.text.decode("utf-8")
                owner = self.functions[(path, scope)]
                parameters = node.child_by_field_name("parameters")
                for parameter in parameters.named_children if parameters else []:
                    name = parameter if parameter.type == "identifier" else next(
                        (child for child in parameter.named_children if child.type == "identifier"), None)
                    if name:
                        aliases[(scope, name.text.decode("utf-8"))] = None
            if node.type in {"const_statement", "variable_statement"} and name_node:
                aliases[(scope, name_node.text.decode("utf-8"))] = None
                value = node.child_by_field_name("value")
                for call in walk(value) if value else []:
                    if call.type != "call" or not call.named_children or call.named_children[0].text not in {b"preload", b"load"}:
                        continue
                    for literal in walk(call):
                        if literal.type == "string":
                            target = self.resource(self.literal(literal) or "")
                            if target:
                                aliases[(scope, name_node.text.decode("utf-8"))] = target
            line = node.start_point.row + 1
            if node.type == "string":
                literal = self.literal(node) or ""
                target = self.resource(literal)
                if target:
                    self.edge(owner, self.module(target), "references", path, line)
                elif re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+", literal):
                    target = self.resource("res://" + literal.replace(".", "/") + ".py")
                    if target:
                        self.edge(owner, self.module(target), "references", path, line, "INFERRED")
            if node.type == "call" and node.named_children:
                name = node.named_children[0].text.decode("utf-8")
                target = self.functions.get((path, class_prefix + name))
                if target:
                    self.edge(owner, target, "calls", path, line)
            if node.type == "attribute" and len(node.named_children) >= 2:
                receiver, member = node.named_children[:2]
                if receiver.type == "identifier" and member.type == "attribute_call":
                    alias = receiver.text.decode("utf-8")
                    target_file = aliases.get((scope, alias), aliases.get(("", alias)))
                    method = member.named_children[0].text.decode("utf-8")
                    target = self.functions.get((target_file, method))
                    if target:
                        self.edge(owner, target, "calls", path, line, "INFERRED")
                    elif alias == "self":
                        target = self.functions.get((path, class_prefix + method))
                        if target:
                            self.edge(owner, target, "calls", path, line)
            for child in node.named_children:
                visit(child, owner, scope, class_prefix)
        visit(tree.root_node)

    def structured_file(self, path: Path):
        owner = self.module(path)
        for line, text in enumerate(read_source(path).splitlines(), 1):
            for match in re.finditer(r'res://[^"\s]+', text):
                target = self.resource(match.group())
                if target:
                    self.edge(owner, self.module(target), "references", path, line)
            if path.suffix == ".md":
                # Document links are explicit structure, not LLM-derived claims.
                for match in re.finditer(r'\]\(([^)\s]+)\)', text):
                    value = match.group(1).split("#", 1)[0]
                    if not value or ":" in value:
                        continue
                    target = (path.parent / value).resolve()
                    if target.is_relative_to(self.root) and target.is_file():
                        relative = target.relative_to(self.root).as_posix()
                        resource = self.resource("res://" + relative)
                        if resource:
                            self.edge(owner, self.module(resource), "documents", path, line)

    def extract(self, paths: list[Path]) -> dict:
        scripts = sorted(path.resolve() for path in paths if path.suffix == ".gd")
        for path in scripts:
            self.declarations(path)
        for path in scripts:
            self.relationships(path)
        for path in sorted(paths):
            if path.suffix != ".gd":
                self.structured_file(path)
        return {"nodes": list(self.nodes.values()), "edges": list(self.edges.values())}


def build(root: Path = ROOT):
    from graphify.detect import detect
    from graphify.extract import extract
    from graphify.build import build_from_json
    from graphify.cluster import cluster, label_communities_by_hub
    from graphify.export import to_json
    from graphify.exporters.html import to_html

    config = json.loads((root / "config/graphify.json").read_text(encoding="utf-8"))
    if version("graphifyy") != config["version"]:
        raise RuntimeError("Graphify version changed; run tools/graphify.ps1 install")
    output = root / config["output"]
    output.mkdir(exist_ok=True)
    (output / ".gdignore").touch()
    detection = detect(root, cache_root=root)
    code = [Path(path) for path in detection["files"]["code"]]
    native = extract(code, root=root, cache_root=root, parallel=False)
    candidates = {Path(path) for path in detection["unclassified"]}
    candidates.update(Path(path) for values in detection["files"].values() for path in values)
    candidates.add(root / "project.godot")
    custom_paths = sorted(path for path in candidates if path.suffix in GODOT_SUFFIXES | {".md"})
    adapter = GodotExtractor(root, native)
    custom = adapter.extract(custom_paths)
    combined = {"nodes": native["nodes"] + custom["nodes"], "edges": native["edges"] + custom["edges"]}
    graph = build_from_json(combined, root=root, directed=True, dedup=False)
    graph.graph["essaim_adapter_version"] = 1
    graph.graph["essaim_graphify_revision"] = config["revision"]
    communities = cluster(graph)
    labels = label_communities_by_hub(graph, communities)
    if not to_json(graph, communities, str(output / "graph.json"), force=True, community_labels=labels):
        raise RuntimeError("Graphify declined to save graph")
    if not to_html(graph, communities, str(output / "graph.html"), community_labels=labels, node_limit=10000):
        raise RuntimeError("Graphify could not create the interactive graph")
    (output / ".graphify_root").write_text(str(root), encoding="utf-8")
    sources = Counter(data.get("source_file", "") for _, data in graph.nodes(data=True))
    lines = ["# ESSAIM code knowledge graph", "", f"{graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges, {len(communities)} communities.",
             "", "Built locally: Graphify AST extraction plus the ESSAIM GDScript AST/resource adapter.",
             "Documentation links are indexed structurally; prose is not semantically analyzed.",
             "Dynamic Godot calls, signals and runtime-generated references may be unresolved.",
             "EXTRACTED edges are explicit structure; INFERRED edges resolve preload aliases to methods.", "",
             "Rebuild with `./tools/graphify.ps1 build`; query with `./tools/graphify.ps1 query 'vehicle collisions'`.",
             "", "## Files with most symbols", "", "| File | Nodes |", "|---|---:|"]
    lines.extend(f"| {path} | {count} |" for path, count in sources.most_common(20))
    lines.extend(["", "## Parser diagnostics", ""] + (adapter.warnings or ["No GDScript parser errors."]))
    (output / "GRAPH_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"ESSAIM graph: {graph.number_of_nodes()} nodes, {graph.number_of_edges()} edges; {len(custom_paths)} Godot/document files, {len(code)} native code/config files.")
    for warning in adapter.warnings:
        print("Warning: " + warning, file=sys.stderr)
    print(f"Open {output / 'graph.html'}")


if __name__ == "__main__":
    build()

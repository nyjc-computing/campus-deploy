"""campus_deploy public-interface closed-world guard and manifest check.

The public interface of campus.deploy is the module's ``__all__``:
declared names must import; the manifest (tests/interface_manifest.json)
is the checked-in snapshot CI compares against reality, so any
interface change is a deliberate, diffable commit that ships with a
CHANGELOG entry and the version bump the diff dictates
(additive -> patch, breaking -> minor).
"""

import ast
import json
import pathlib
import unittest

import campus.deploy

SRC = pathlib.Path(campus.deploy.__file__).resolve().parent
MANIFEST = pathlib.Path(__file__).resolve().parents[1] / "interface_manifest.json"


def _all_of(tree: ast.Module) -> list[str]:
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if getattr(target, "id", None) == "__all__":
                    return [e.value for e in node.value.elts if isinstance(e, ast.Constant)]
    raise AssertionError("no __all__ defined")


def build_interface_manifest() -> dict[str, list[str]]:
    """The full declared-interface snapshot, as a JSON-ready dict."""
    return {"campus.deploy": sorted(_all_of(ast.parse(
        (SRC / "deploy.py").read_text(encoding="utf-8")
    )))}


class TestModuleInterface(unittest.TestCase):
    """__all__ closure rules for the campus.deploy module."""

    def test_all_importable_and_no_underscores(self):
        for name in campus.deploy.__all__:
            self.assertFalse(name.startswith("_"), name)
            self.assertIsNotNone(getattr(campus.deploy, name))

    def test_public_defs_declared(self):
        """Every public def/class in deploy.py must appear in __all__."""
        tree = ast.parse((SRC / "deploy.py").read_text(encoding="utf-8"))
        declared = set(_all_of(tree))
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
                names = {node.name}
            else:
                continue
            for name in names:
                if not name.startswith("_"):
                    self.assertIn(name, declared, f"deploy.py defines {name} but does not declare it")


class TestInterfaceManifest(unittest.TestCase):
    """The checked-in manifest must match reality exactly (diff = deliberate)."""

    def test_manifest_matches_reality(self):
        committed = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(committed, build_interface_manifest())


if __name__ == "__main__":
    unittest.main()

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("update_mihomo", Path(__file__).with_name("update-mihomo.py"))
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class StableUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "mihomo-meta").mkdir()
        (self.root / "luci-app-nikki").mkdir()
        (self.root / ".github").mkdir()
        self.makefile = self.root / "mihomo-meta/Makefile"
        self.makefile.write_text(
            "PKG_NAME:=mihomo-meta\nPKG_VERSION:=1.19.32\n"
            "PKG_SOURCE_VERSION:=v1.19.32\nPKG_BUILD_VERSION:=v1.19.32\n"
            f"PKG_MIRROR_HASH:={'a' * 64}\nGO_PKG_TAGS:=with_gvisor\n",
            encoding="utf-8",
        )
        (self.root / "luci-app-nikki/Makefile").write_text("PKG_VERSION:=1.26.2\n", encoding="utf-8")
        self.state = self.root / ".github/mihomo-release.json"
        self.state.write_text(json.dumps({"version": "1.19.32", "tag": "v1.26.2"}, indent=2) + "\n")
        self.published = {
            "draft": False, "prerelease": False,
            "assets": [{"name": updater.ASSET, "state": "uploaded", "size": 22000000}],
        }

    def prepare(self, latest="v1.19.32", published=None, verify=False, checksum="b" * 64):
        upstream = {"tag_name": latest, "draft": False, "prerelease": False}
        if published is None:
            published = self.published
        with patch.object(updater, "github_json", side_effect=[upstream, published]) as api:
            with patch.object(updater, "source_checksum", return_value=checksum) as source:
                result = updater.prepare_update(self.root, "levi882/OpenWrt-nikki", verify)
        return result, api, source

    def test_current_published_version_is_a_noop(self):
        before = self.makefile.read_bytes(), self.state.read_bytes()
        result, api, source = self.prepare()
        self.assertFalse(result["build"])
        self.assertFalse(result["changed"])
        self.assertEqual(before, (self.makefile.read_bytes(), self.state.read_bytes()))
        self.assertEqual(api.call_args.args[0], "levi882/OpenWrt-nikki/releases/tags/v1.26.2")
        source.assert_not_called()

    def test_new_stable_version_updates_only_the_core_and_release_record(self):
        result, api, source = self.prepare("v1.19.33")
        self.assertTrue(result["build"])
        self.assertTrue(result["changed"])
        self.assertEqual(result["release_tag"], "v1.26.2-mihomo-1.19.33")
        source.assert_called_once_with("v1.19.33", "1.19.33")
        self.assertEqual(api.call_args.args[0], "levi882/OpenWrt-nikki/releases/tags/v1.26.2-mihomo-1.19.33")
        text = self.makefile.read_text()
        self.assertEqual(updater.make_value(text, "PKG_VERSION"), "1.19.33")
        self.assertEqual(updater.make_value(text, "PKG_SOURCE_VERSION"), "v1.19.33")
        self.assertEqual(updater.make_value(text, "PKG_BUILD_VERSION"), "v1.19.33")
        self.assertEqual(updater.make_value(text, "PKG_MIRROR_HASH"), "b" * 64)
        self.assertIn("GO_PKG_TAGS:=with_gvisor\n", text)
        self.assertEqual(json.loads(self.state.read_text())["version"], "1.19.33")

    def test_draft_or_missing_archive_retries_without_another_version_commit(self):
        for release in [
            {**self.published, "draft": True},
            {**self.published, "assets": []},
            {**self.published, "assets": [{"name": updater.ASSET, "state": "new", "size": 0}]},
            {},
        ]:
            with self.subTest(release=release):
                result, _, source = self.prepare(published=release)
                self.assertTrue(result["build"])
                self.assertFalse(result["changed"])
                self.assertEqual(result["release_tag"], "v1.26.2")
                source.assert_not_called()

    def test_a_pending_new_release_remains_retryable_after_the_source_is_pushed(self):
        self.prepare("v1.19.33")
        result, _, source = self.prepare("v1.19.33", published={"draft": True})
        self.assertTrue(result["build"])
        self.assertFalse(result["changed"])
        self.assertEqual(result["release_tag"], "v1.26.2-mihomo-1.19.33")
        source.assert_not_called()

    def test_upstream_rollback_does_not_downgrade_the_core(self):
        result, _, source = self.prepare("v1.19.31")
        self.assertEqual(result["version"], "1.19.32")
        self.assertFalse(result["changed"])
        self.assertFalse(result["build"])
        source.assert_not_called()

    def test_pre_release_or_unexpected_tag_is_rejected_without_changes(self):
        before = self.makefile.read_bytes(), self.state.read_bytes()
        for tag in ["Alpha", "v1.19.33-rc1", "v1.19.33\nother=value"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.prepare(tag)
        with patch.object(updater, "github_json", return_value={
            "tag_name": "v1.19.33", "draft": False, "prerelease": True,
        }), self.assertRaises(ValueError):
            updater.prepare_update(self.root, "levi882/OpenWrt-nikki")
        self.assertEqual(before, (self.makefile.read_bytes(), self.state.read_bytes()))

    def test_checksum_failure_does_not_write_partial_update(self):
        before = self.makefile.read_bytes(), self.state.read_bytes()
        with self.assertRaises(ValueError):
            self.prepare("v1.19.33", checksum="invalid")
        with patch.object(updater, "github_json", side_effect=[
            {"tag_name": "v1.19.33", "draft": False, "prerelease": False}, None,
        ]), patch.object(updater, "source_checksum", side_effect=RuntimeError("download failed")):
            with self.assertRaises(RuntimeError):
                updater.prepare_update(self.root, "levi882/OpenWrt-nikki")
        self.assertEqual(before, (self.makefile.read_bytes(), self.state.read_bytes()))

    def test_numeric_comparison_handles_two_digit_versions(self):
        self.assertGreater(updater.stable_version("v1.20.0"), updater.stable_version("v1.19.99"))

    def test_optional_source_verification_checks_the_existing_hash(self):
        result, _, source = self.prepare(verify=True, checksum="a" * 64)
        self.assertFalse(result["build"])
        source.assert_called_once_with("v1.19.32", "1.19.32")
        with self.assertRaisesRegex(ValueError, "pinned hash"):
            self.prepare(verify=True)


if __name__ == "__main__":
    unittest.main()

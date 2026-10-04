"""Run the installers against isolated files and command doubles."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
FEED = "https://openwrt-packages.pages.dev/openwrt-25.12/x86_64/myfeed/packages.adb"


class FeedInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="nikki-feed-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        etc = self.root / "etc"
        (etc / "apk/repositories.d").mkdir(parents=True)
        self.repositories = etc / "apk/repositories.d/customfeeds.list"
        self.repositories.write_text(
            "# retain this comment\nhttps://example.invalid/packages.adb\n"
            "https://nikkinikki.pages.dev/openwrt-25.12/x86_64/nikki/packages.adb\n"
            f"{FEED}\n@myfeed {FEED}\n",
        )
        self.release = etc / "openwrt_release"
        self.release.write_text("DISTRIB_RELEASE='25.12.5'\nDISTRIB_ARCH='x86_64'\n")
        self.calls = self.root / "apk-calls"
        self.calls.touch()
        self.write_command("fw4", "exit 0\n")
        self.write_command("apk", r'''
printf '%s\n' "$*" >> "$NIKKI_TEST_CALLS"
case "$1" in
    info) exit 0 ;;
    add) exit "${NIKKI_TEST_ADD_STATUS:-0}" ;;
    update) exit "${NIKKI_TEST_UPDATE_STATUS:-0}" ;;
esac
''')
        self.write_command("wget", r'''
test "$1" = -O || exit 2
if [ "${NIKKI_TEST_DOWNLOAD_FAIL:-0}" = 1 ]; then exit 9; fi
case "$3" in
    https://openwrt-packages.pages.dev/public-key.pem)
        printf '%s\n' 'test signing key' > "$2" ;;
    https://raw.githubusercontent.com/levi882/OpenWrt-nikki/main/feed.sh)
        cp "$NIKKI_TEST_FEED" "$2" ;;
    *) exit 3 ;;
esac
''')
        # Change only absolute filesystem paths, then execute the actual scripts.
        feed = (REPO / "feed.sh").read_text().replace("/etc/", str(etc) + "/")
        feed = feed.replace("/usr/bin/apk", str(self.bin / "apk"))
        feed = feed.replace("/sbin/fw4", str(self.bin / "fw4"))
        feed = feed.replace("/tmp/nikki-myfeed-key", str(self.root / "nikki-myfeed-key"))
        self.feed_script = self.root / "feed.sh"
        self.feed_script.write_text(feed)
        self.install_script = self.root / "install.sh"
        self.install_script.write_text((REPO / "install.sh").read_text().replace(
            "/tmp/nikki-install", str(self.root / "nikki-install"),
        ))
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "NIKKI_TEST_CALLS": str(self.calls),
            "NIKKI_TEST_FEED": str(self.feed_script),
        }

    def write_command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def run_script(self, script, **environment):
        return subprocess.run(
            ["sh", str(script)], env={**self.env, **environment}, text=True, capture_output=True,
        )

    def test_repeated_setup_preserves_other_feeds_and_keeps_one_myfeed_tag(self):
        for _ in range(2):
            result = self.run_script(self.feed_script)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.repositories.read_text().splitlines(), [
            "# retain this comment", "https://example.invalid/packages.adb", f"@myfeed {FEED}",
        ])
        self.assertEqual((self.root / "etc/apk/keys/myfeed.pem").read_text(), "test signing key\n")
        self.assertEqual(self.calls.read_text().splitlines(), ["update", "update"])

    def test_failed_key_download_preserves_existing_repository_configuration(self):
        before = self.repositories.read_bytes()
        result = self.run_script(self.feed_script, NIKKI_TEST_DOWNLOAD_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.repositories.read_bytes())
        self.assertEqual(self.calls.read_text(), "")

    def test_unsupported_target_is_rejected_before_changes(self):
        self.release.write_text("DISTRIB_RELEASE='24.10.5'\nDISTRIB_ARCH='x86_64'\n")
        before = self.repositories.read_bytes()
        result = self.run_script(self.feed_script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("25.12 / x86_64", result.stderr)
        self.assertEqual(before, self.repositories.read_bytes())

    def test_signature_or_index_failure_prevents_package_installation(self):
        result = self.run_script(self.install_script, NIKKI_TEST_UPDATE_STATUS="4")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines(), ["update"])

    def test_installer_uses_tagged_packages_and_signature_verification(self):
        result = self.run_script(self.install_script)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertIn("add --upgrade mihomo-meta@myfeed nikki@myfeed luci-app-nikki@myfeed", calls)
        self.assertIn("add --upgrade luci-i18n-nikki-zh-cn@myfeed", calls)
        self.assertNotIn("allow-untrusted", self.calls.read_text())

    def test_failed_package_installation_does_not_report_success(self):
        result = self.run_script(self.install_script, NIKKI_TEST_ADD_STATUS="5")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Nikki installed or updated", result.stdout)


if __name__ == "__main__":
    unittest.main()

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).resolve().parents[1] / "validate-release.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class ReleaseValidationTest(unittest.TestCase):
    def release(self, tag="v0.1.0", **values):
        return dict({"tag_name": tag, "draft": False, "prerelease": False, "assets": []}, **values)

    def metadata(self, version="0.1.0", certificate="a" * 64):
        return dict(schemaVersion=1, platform="mobile", packageName="com.mynora.singverse.mobile", minSdk=24,
                    versionName=version, versionCode=validation.version_code(version), certificateSha256=certificate, size=42, sha256="c" * 64, abis=["arm64-v8a"], notes="修复播放")

    def test_release_tag_must_match_root_version(self):
        with self.assertRaisesRegex(ValueError, "tag must equal"):
            validation.release_plan("0.1.0", "v0.2.0", [])

    def test_an_older_or_duplicate_product_version_cannot_be_published(self):
        for tag in ("v0.2.0", "0.1.0"):
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "greater"):
                validation.release_plan("0.1.0", "v0.1.0", [self.release(), self.release(tag)])

    def test_formal_new_release_ignores_drafts_and_prereleases(self):
        current = self.release()
        result = validation.release_plan("0.1.0", "v0.1.0", [current, self.release("draft", draft=True),
                                        self.release("v1.0.0-rc.1", prerelease=True)], self.metadata())
        self.assertEqual(result, current)

    def test_certificate_and_code_are_continuous_from_previous_formal_release(self):
        old = self.release("v0.0.999", assets=[dict(name="release.json", state="uploaded", id=12)])
        with patch.object(validation, "asset", wraps=validation.asset) as lookup:
            validation.release_plan("0.1.0", "v0.1.0", [self.release(), old], self.metadata(),
                                    lambda item, maximum: json.dumps(self.metadata("0.0.999")).encode())
            self.assertEqual(lookup.call_args.args[0]["tag_name"], "v0.0.999")
        with self.assertRaisesRegex(ValueError, "certificate must match"):
            validation.release_plan("0.1.0", "v0.1.0", [self.release(), old], self.metadata(certificate="b" * 64),
                                    lambda item, maximum: json.dumps(self.metadata("0.0.999")).encode())
        bad = self.metadata("0.0.999"); bad["versionCode"] = 1000
        with self.assertRaisesRegex(ValueError, "metadata differs"):
            validation.release_plan("0.1.0", "v0.1.0", [self.release(), old], self.metadata(),
                                    lambda item, maximum: json.dumps(bad).encode())

    def test_missing_previous_metadata_and_network_errors_never_become_a_first_release(self):
        old = self.release("v0.0.999")
        with self.assertRaisesRegex(ValueError, "Missing"):
            validation.release_plan("0.1.0", "v0.1.0", [self.release(), old], self.metadata(), lambda *args: None)
        old["assets"] = [dict(name="release.json", state="uploaded", id=12)]
        def unavailable(*args):
            raise OSError("Network unavailable")
        with self.assertRaisesRegex(OSError, "Network"):
            validation.release_plan("0.1.0", "v0.1.0", [self.release(), old], self.metadata(), unavailable)

    def test_the_highest_previous_formal_version_is_used_and_current_tag_is_excluded(self):
        low = self.release("v0.0.1", assets=[dict(name="release.json", state="uploaded", id=1)])
        high = self.release("v0.0.999", assets=[dict(name="release.json", state="uploaded", id=999)])
        seen = []
        def read(item, maximum):
            seen.append(item["id"])
            return json.dumps(self.metadata("0.0.999")).encode()
        validation.release_plan("0.1.0", "v0.1.0", [low, self.release(), high], self.metadata(), read)
        self.assertEqual(seen, [999])

    def test_a_retry_reuses_identical_assets_and_uploads_only_missing_ones(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("singverse-mobile.apk", "release.json", "SHA256SUMS"):
                (directory / name).write_bytes(name.encode())
            existing = dict(name="singverse-mobile.apk", state="uploaded", id=1, size=len(b"singverse-mobile.apk"))
            result = validation.reusable_assets(self.release(assets=[existing]), directory, lambda *args: b"singverse-mobile.apk")
            self.assertEqual([p.name for p in result], ["release.json", "SHA256SUMS"])
            with self.assertRaisesRegex(ValueError, "different content"):
                validation.reusable_assets(self.release(assets=[existing]), directory, lambda *args: b"x" * existing["size"])
            with self.assertRaisesRegex(ValueError, "ambiguous"):
                validation.reusable_assets(self.release(assets=[existing, existing]), directory, lambda *args: b"singverse-mobile.apk")

    def test_android_code_boundaries_and_metadata_types(self):
        self.assertEqual(validation.version_code("1.2.3"), 1002003)
        for value in ("0.0.0", "1.1000.0", "1.0.1000", "2101.0.0", "01.0.0"):
            with self.subTest(value=value), self.assertRaises(ValueError): validation.version_code(value)
        wrong = self.metadata(); wrong["schemaVersion"] = True
        with self.assertRaises(ValueError): validation.check_metadata(wrong, "0.1.0")

    def test_incomplete_or_malformed_metadata_is_rejected(self):
        for field in ("sha256", "size", "abis", "notes", "certificateSha256"):
            candidate = self.metadata()
            del candidate[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                validation.check_metadata(candidate, "0.1.0")
        for changes in ({"sha256": "A" * 64}, {"size": True}, {"size": 268435457},
                        {"abis": []}, {"abis": ["universal", "x86"]}, {"notes": "汉" * 5334}):
            with self.subTest(changes=changes.keys()), self.assertRaises(ValueError):
                validation.check_metadata({**self.metadata(), **changes}, "0.1.0")

    def test_only_expected_https_destinations_are_allowed(self):
        for url in ("http://github.com/x", "https://github.com.evil/x", "https://user:pass@api.github.com/x"):
            with self.subTest(url=url), self.assertRaises(ValueError): validation.github_url(url)
        validation.github_url("https://release-assets.githubusercontent.com/x")


if __name__ == "__main__":
    unittest.main()

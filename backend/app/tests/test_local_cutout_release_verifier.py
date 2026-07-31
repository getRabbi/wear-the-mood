"""Negative tests for scripts/verify_local_cutout_release.py (local BG §13).

A release gate that has never been seen to FAIL is not a gate, it is a comment.
Every guard here is proven twice: once against the real repository, where it must
pass, and once against a deliberately broken copy of it, where it must fail with a
message that names the actual problem.

The breakages are not hypothetical. Each one is a way this feature has actually
stopped working, or a way the next change could stop it:

  * a gate missing, false, or a truthy-looking string Dart compiles to false;
  * the ML Kit manifest metadata dropped, so the model is never pre-fetched;
  * a native source no longer a member of its build target;
  * the plugin no longer registered on the Flutter engine;
  * the method-channel name changed on one side only;
  * the backend endpoint removed or gated off;
  * the diagnostic export compiled into a store build;
  * a Swift suite that "passes" while executing zero tests.

The script lives at the repository root rather than in `backend/`, so it is loaded
by path. That is deliberate: it verifies the app and the backend together, and
neither owns it.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path
from types import ModuleType

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT = REPO_ROOT / "scripts" / "verify_local_cutout_release.py"


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("verify_local_cutout_release", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


verifier = _load()


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    """A minimal copy of the parts of the repo the verifier reads.

    Copying rather than mutating the real tree is the point: a guard is proven by
    breaking something, and breaking the working tree to prove a test would be an
    excellent way to ship the break.
    """
    for relative in (
        "app/env",
        "app/android/app/src/main",
        "app/android/app/build.gradle.kts",
        "app/ios/Runner",
        "app/ios/RunnerTests",
        "app/ios/Runner.xcodeproj/project.pbxproj",
        "app/ios/Flutter",
        "backend/app/routers/v1/wardrobe.py",
        "backend/app/core/config.py",
        "backend/app/services/bg",
        "docs/bg/local_cutout_compatibility.json",
        "docs/bg/local_cutout_device_evidence.json",
    ):
        source = REPO_ROOT / relative
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target, dirs_exist_ok=True)
        elif source.exists():
            shutil.copy2(source, target)
    return tmp_path


def _config(repo: Path, **overrides: str) -> Path:
    """The generated dart-define file, production-correct unless overridden."""
    policy = json.loads((repo / "app/env/feature_policy.prod.json").read_text(encoding="utf-8"))
    document: dict[str, object] = {"ENVIRONMENT": "prod", **policy["gates"]}
    for key, value in overrides.items():
        if value is None:
            document.pop(key, None)
        else:
            document[key] = value
    path = repo / "app/env/prod.json"
    path.write_text(json.dumps(document, indent=2), encoding="utf-8")
    return path


def _run(repo: Path, target: str, **kwargs: str) -> tuple[int, verifier.Report]:
    report = verifier.Report()
    args = verifier.argparse.Namespace(
        target=target,
        repo_root=str(repo),
        config=str(repo / "app/env/prod.json"),
        artifact=kwargs.get("artifact"),
        backend_env_file=kwargs.get("backend_env_file"),
        swift_test_log=kwargs.get("swift_test_log"),
        skip_device_evidence=True,
        warn_only=False,
    )
    verifier.TARGETS[target](report, args, repo)
    return len(report.failures), report


def _failed(report: verifier.Report, fragment: str) -> bool:
    return any(fragment in check.name or fragment in check.detail for check in report.failures)


# ── the baseline: the real repository must PASS ──────────────────────────────
def test_the_real_repository_passes_the_ci_target() -> None:
    report = verifier.Report()
    args = verifier.argparse.Namespace(
        target="ci",
        repo_root=str(REPO_ROOT),
        config=str(REPO_ROOT / "app/env/prod.json"),
        artifact=None,
        backend_env_file=None,
        swift_test_log=None,
        skip_device_evidence=True,
        warn_only=False,
    )
    verifier.target_ci(report, args, REPO_ROOT)
    assert not report.failures, [c.line for c in report.failures]


def test_a_correct_generated_config_passes(repo: Path) -> None:
    _config(repo)
    failures, report = _run(repo, "ios-production")
    assert failures == 0, [c.line for c in report.failures]


# ── gate breakages ───────────────────────────────────────────────────────────
def test_a_missing_master_gate_fails(repo: Path) -> None:
    _config(repo, LOCAL_BG_REMOVAL_ENABLED=None)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "MISSING")


def test_a_false_android_gate_fails(repo: Path) -> None:
    _config(repo, LOCAL_BG_ANDROID_ENABLED="false")
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "required true")


def test_a_false_ios_gate_fails(repo: Path) -> None:
    _config(repo, LOCAL_BG_IOS_ENABLED="false")
    failures, report = _run(repo, "ios-production")
    assert failures
    assert _failed(report, "required true")


@pytest.mark.parametrize("value", ["True", "1", "yes", "true ", ""])
def test_a_malformed_gate_fails(repo: Path, value: str) -> None:
    # Every one of these compiles to FALSE in Dart while reading as "on" to a human.
    _config(repo, LOCAL_BG_REMOVAL_ENABLED=value)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "literal")


def test_diagnostics_enabled_in_a_store_build_fails(repo: Path) -> None:
    _config(repo, LOCAL_BG_IOS_DIAGNOSTICS_ENABLED="true")
    failures, report = _run(repo, "ios-production")
    assert failures
    assert _failed(report, "LOCAL_BG_IOS_DIAGNOSTICS_ENABLED")


def test_drift_from_the_committed_policy_fails(repo: Path) -> None:
    # The whole point of the committed policy: a config that disagrees with it, from
    # wherever, does not ship.
    _config(repo, CUTOUT_EDITOR_ENABLED="false")
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "committed policy")


# ── Android breakages ────────────────────────────────────────────────────────
def test_a_missing_manifest_dependency_fails(repo: Path) -> None:
    manifest = repo / "app/android/app/src/main/AndroidManifest.xml"
    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace("subject_segment", "face_detection"),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "install-time model metadata")


def test_a_missing_android_registration_fails(repo: Path) -> None:
    activity = repo / "app/android/app/src/main/kotlin/com/fashionos/app/MainActivity.kt"
    activity.write_text(
        activity.read_text(encoding="utf-8").replace(
            "WtmBackgroundRemovalPlugin.register(", "// removed("
        ),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "plugin registered")


ANDROID_BG = "app/android/app/src/main/kotlin/com/fashionos/app/background"


def test_a_channel_name_mismatch_fails(repo: Path) -> None:
    plugin = repo / ANDROID_BG / "WtmBackgroundRemovalPlugin.kt"
    plugin.write_text(
        plugin.read_text(encoding="utf-8").replace(
            'CHANNEL = "wtm/background_removal"', 'CHANNEL = "wtm/background_removal_v2"'
        ),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "channel name")


def test_an_unpinned_mlkit_version_fails(repo: Path) -> None:
    gradle = repo / "app/android/app/build.gradle.kts"
    gradle.write_text(
        gradle.read_text(encoding="utf-8").replace("16.0.0-beta1", "16.0.+"),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "pinned")


def test_reinstating_the_corrupt_foreground_mask_fails(repo: Path) -> None:
    # Measured 69% invalid on real hardware. A refactor must not quietly bring it back.
    client = repo / ANDROID_BG / "MlKitSubjectSegmentationClient.kt"
    reinstated = ".enableForegroundConfidenceMask()\n            .enableMultipleSubjects("
    client.write_text(
        client.read_text(encoding="utf-8").replace(".enableMultipleSubjects(", reinstated),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "android-production")
    assert failures
    assert _failed(report, "per-subject masks only")


# ── iOS breakages ────────────────────────────────────────────────────────────
def test_a_source_dropped_from_the_runner_target_fails(repo: Path) -> None:
    # The silent one: the file is still in the navigator, still in git, still opens
    # in Xcode -- and is simply not compiled into the app any more.
    pbxproj = repo / "app/ios/Runner.xcodeproj/project.pbxproj"
    pbxproj.write_text(
        pbxproj.read_text(encoding="utf-8").replace(
            "\t\t\t\tBC9000000000000000000305 /* AppleVisionCutoutEngine.swift in Sources */,\n", ""
        ),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "ios-production")
    assert failures
    assert _failed(report, "Runner target membership")


def test_a_source_missing_from_the_test_target_fails(repo: Path) -> None:
    # A suite compiling different code than the app reports confidence it has not
    # earned -- worse than no suite at all.
    pbxproj = repo / "app/ios/Runner.xcodeproj/project.pbxproj"
    pbxproj.write_text(
        pbxproj.read_text(encoding="utf-8").replace(
            "\t\t\t\tBC9000000000000000000505 /* AppleVisionCutoutEngine.swift in Sources */,\n", ""
        ),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "ios-production")
    assert failures
    assert _failed(report, "RunnerTests compiles the production sources")


def test_a_missing_ios_registration_fails(repo: Path) -> None:
    delegate = repo / "app/ios/Runner/AppDelegate.swift"
    delegate.write_text(
        delegate.read_text(encoding="utf-8").replace(
            "WTMBackgroundRemovalPlugin.register(", "// removed("
        ),
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "ios-production")
    assert failures
    assert _failed(report, "WTM plugin registered")


def test_a_committed_diagnostic_condition_fails_a_store_build(repo: Path) -> None:
    config = repo / "app/ios/Flutter/Release.xcconfig"
    config.write_text(
        config.read_text(encoding="utf-8")
        + "\nSWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) WTM_LOCAL_BG_DIAGNOSTICS\n",
        encoding="utf-8",
    )
    _config(repo)
    failures, report = _run(repo, "ios-production")
    assert failures
    assert _failed(report, "no diagnostic condition in a store build")


def test_the_diagnostic_target_REQUIRES_that_same_condition(repo: Path) -> None:
    # The mirror image: a diagnostic build without it produces a bundle-less run
    # that looks exactly like a Vision failure, wasting a device session.
    policy = json.loads(
        (repo / "app/env/feature_policy.ios-diagnostic.json").read_text(encoding="utf-8")
    )
    (repo / "app/env/prod.json").write_text(
        json.dumps({"ENVIRONMENT": "prod", **policy["gates"]}, indent=2), encoding="utf-8"
    )
    failures, report = _run(repo, "ios-diagnostic")
    assert failures
    assert _failed(report, "diagnostic compilation condition")


# ── backend breakages ────────────────────────────────────────────────────────
def test_a_disabled_backend_endpoint_fails(repo: Path) -> None:
    failures, report = _run(repo, "backend", backend_env_file=None)
    env_file = repo / "backend.env"
    env_file.write_text("LOCAL_CUTOUT_UPLOAD_ENABLED=false\n", encoding="utf-8")
    failures, report = _run(repo, "backend", backend_env_file=str(env_file))
    assert failures
    assert _failed(report, "LOCAL_CUTOUT_UPLOAD_ENABLED")


def test_an_engaged_emergency_switch_fails_a_release(repo: Path) -> None:
    env_file = repo / "backend.env"
    env_file.write_text(
        "LOCAL_CUTOUT_UPLOAD_ENABLED=true\nLOCAL_CUTOUT_EMERGENCY_DISABLE=true\n",
        encoding="utf-8",
    )
    failures, report = _run(repo, "backend", backend_env_file=str(env_file))
    assert failures
    assert _failed(report, "EMERGENCY")


def test_a_removed_endpoint_fails(repo: Path) -> None:
    wardrobe = repo / "backend/app/routers/v1/wardrobe.py"
    wardrobe.write_text(
        wardrobe.read_text(encoding="utf-8").replace(
            '@router.post("/wardrobe/local-cutout"', '@router.post("/wardrobe/gone"'
        ),
        encoding="utf-8",
    )
    env_file = repo / "backend.env"
    env_file.write_text("LOCAL_CUTOUT_UPLOAD_ENABLED=true\n", encoding="utf-8")
    failures, report = _run(repo, "backend", backend_env_file=str(env_file))
    assert failures
    assert _failed(report, "endpoint exists")


def test_flattening_the_cutout_to_a_lossy_format_fails(repo: Path) -> None:
    # A cutout without alpha renders as an opaque rectangle in the closet, which is
    # indistinguishable from "background removal is broken".
    ingest = repo / "backend/app/services/bg/mask_ingest.py"
    ingest.write_text(
        ingest.read_text(encoding="utf-8").replace("compose_cutout_webp", "compose_flat_jpeg"),
        encoding="utf-8",
    )
    env_file = repo / "backend.env"
    env_file.write_text("LOCAL_CUTOUT_UPLOAD_ENABLED=true\n", encoding="utf-8")
    failures, report = _run(repo, "backend", backend_env_file=str(env_file))
    assert failures
    assert _failed(report, "alpha-bearing output")


# ── the Swift test-count assertion ───────────────────────────────────────────
def test_zero_executed_swift_tests_fails(tmp_path: Path) -> None:
    # The exact shape of the original defect: the command succeeded, no assertion
    # ever ran, and the result was filed as a template limitation.
    log = tmp_path / "xcodebuild-test.log"
    log.write_text("** TEST SUCCEEDED **\n", encoding="utf-8")
    report = verifier.Report()
    verifier.check_swift_test_log(report, log)
    assert report.failures
    assert _failed(report, "executed")


def test_a_missing_swift_log_fails(tmp_path: Path) -> None:
    report = verifier.Report()
    verifier.check_swift_test_log(report, tmp_path / "never-written.log")
    assert report.failures


def test_a_full_swift_run_passes(tmp_path: Path) -> None:
    log = tmp_path / "xcodebuild-test.log"
    log.write_text(
        "Test Suite 'All tests' passed\nExecuted 120 tests, with 0 failures (0 unexpected)\n",
        encoding="utf-8",
    )
    report = verifier.Report()
    verifier.check_swift_test_log(report, log)
    assert not report.failures, [c.line for c in report.failures]


def test_swift_failures_fail(tmp_path: Path) -> None:
    log = tmp_path / "xcodebuild-test.log"
    log.write_text(
        "Executed 120 tests, with 3 failures (0 unexpected)\n",
        encoding="utf-8",
    )
    report = verifier.Report()
    verifier.check_swift_test_log(report, log)
    assert _failed(report, "failure")


# ── device evidence ──────────────────────────────────────────────────────────
def test_device_evidence_is_required_and_keyed_to_the_native_code(repo: Path) -> None:
    report = verifier.Report()
    verifier.check_device_evidence(report, repo, "ios")
    assert report.failures, "an unvalidated Vision engine must not be shippable"
    assert _failed(report, "device")


def test_recorded_evidence_stops_counting_when_native_code_changes(repo: Path) -> None:
    # Record a pass for the CURRENT code, prove it satisfies the gate, then change
    # one native source and prove the same evidence no longer applies.
    verifier.record_device_evidence(
        repo, "ios", {"recorded": "2026-08-01", "result": "pass", "runs": "1"}
    )
    report = verifier.Report()
    verifier.check_device_evidence(report, repo, "ios")
    assert not report.failures, [c.line for c in report.failures]

    engine = repo / "app/ios/Runner/BackgroundRemoval/AppleVisionCutoutEngine.swift"
    engine.write_text(engine.read_text(encoding="utf-8") + "\n// a change\n", encoding="utf-8")
    after = verifier.Report()
    verifier.check_device_evidence(after, repo, "ios")
    assert after.failures, "changed native code must invalidate its device evidence"


def test_pre_device_validation_clears_only_the_device_check(repo: Path, capsys) -> None:
    """The artifact has to exist before it can be run on a phone.

    Refusing to BUILD until device evidence exists is circular, so there is a named
    state for it. What must NOT happen is that the escape becomes a general bypass:
    a missing gate has to keep failing even here.
    """
    _config(repo)
    argv = [
        "--target",
        "android-production",
        "--repo-root",
        str(repo),
        "--config",
        str(repo / "app/env/prod.json"),
        "--pre-device-validation",
    ]
    assert verifier.main(argv) == 0
    out = capsys.readouterr().out
    assert "NOT RELEASE APPROVED" in out
    assert "device evidence" in out.lower()

    # ...and the same flag must not rescue a genuinely broken build.
    _config(repo, LOCAL_BG_ANDROID_ENABLED="false")
    assert verifier.main(argv) == 2


def test_a_toolchain_bump_also_invalidates_evidence(repo: Path) -> None:
    verifier.record_device_evidence(
        repo, "android", {"recorded": "2026-08-01", "result": "pass", "runs": "5"}
    )
    manifest = repo / "docs/bg/local_cutout_compatibility.json"
    document = json.loads(manifest.read_text(encoding="utf-8"))
    document["last_validated_flutter_version"] = "9.9.9"
    manifest.write_text(json.dumps(document, indent=2), encoding="utf-8")
    report = verifier.Report()
    verifier.check_device_evidence(report, repo, "android")
    assert report.failures, "a Flutter bump must force the device matrix again"

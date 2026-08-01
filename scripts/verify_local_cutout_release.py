#!/usr/bin/env python3
"""Release-blocking verification of local-first background removal (local BG §3).

The single authority on whether an artifact may ship with on-device background
removal. Run it from the local Android production build, from every Codemagic
release workflow, from the internal diagnostic workflow, and from CI.

It exists because of a recurring failure shape: the feature "stopped working"
several times, and only once was the engine at fault. The other times a gate was
off, a channel was not registered, an endpoint answered 404, or a correct
transparent cutout was painted over -- and in every one of those cases the build
was green, the API was healthy, and the cloud fallback quietly produced a result
that looked fine. Nothing failed, so nothing was noticed.

So this script asserts the things a passing test suite does not:

* the LITERAL gate values in the artifact's own generated config;
* the exact ML Kit dependency, pinned, with the manifest metadata that delivers
  its model;
* that both native engines' source files are actually compiled into their build
  targets, and registered on the channel Dart calls;
* that the RunnerTests bundle compiles the same production sources it claims to
  test, rather than a duplicate list that has drifted;
* that the backend's ingestion endpoint exists and is switched on;
* that the recorded physical-device evidence still matches the native code and
  toolchain being released.

Exit code 0 means every applicable invariant holds. Any other exit code must fail
the build. ``--warn-only`` reports without failing, for diagnosis only.

Usage::

    python3 scripts/verify_local_cutout_release.py --target android-production
    python3 scripts/verify_local_cutout_release.py --target ios-production
    python3 scripts/verify_local_cutout_release.py --target ios-diagnostic
    python3 scripts/verify_local_cutout_release.py --target ci
    python3 scripts/verify_local_cutout_release.py --target android-production \
        --artifact app/build/app/outputs/bundle/release/app-release.aab
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable

DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[1]

# ── the invariant ────────────────────────────────────────────────────────────
#: The production application contract (§2.1). A release artifact whose generated
#: config disagrees with this does not ship. Stated here as well as in the
#: committed policy file so a policy edit cannot quietly redefine "production".
PRODUCTION_GATES: dict[str, str] = {
    "LOCAL_BG_REMOVAL_ENABLED": "true",
    "LOCAL_BG_ANDROID_ENABLED": "true",
    "LOCAL_BG_IOS_ENABLED": "true",
    "LOCAL_BG_IOS_DIAGNOSTICS_ENABLED": "false",
}

#: The internal diagnostic contract. Identical except diagnostics are compiled in.
DIAGNOSTIC_GATES: dict[str, str] = {
    **PRODUCTION_GATES,
    "LOCAL_BG_IOS_DIAGNOSTICS_ENABLED": "true",
}

#: The wire contract between Dart and both native engines. Changing it breaks every
#: shipped build, so all three copies are compared rather than assumed equal.
CHANNEL_NAME = "wtm/background_removal"

#: ML Kit Subject Segmentation is beta and its model comes from Play services, so
#: the client version is pinned and the manifest metadata is mandatory.
MLKIT_ARTIFACT = "com.google.android.gms:play-services-mlkit-subject-segmentation"
MLKIT_MANIFEST_KEY = "com.google.mlkit.vision.DEPENDENCIES"
MLKIT_MANIFEST_VALUE = "subject_segment"
ANDROID_MIN_SDK = 24

ANDROID_NATIVE_FILES = (
    "WtmBackgroundRemovalPlugin.kt",
    "GoogleSubjectSegmenterEngine.kt",
    "MlKitSubjectSegmentationClient.kt",
    "AndroidBitmapCodec.kt",
    "LocalCutoutCacheStore.kt",
    "LocalCutoutContracts.kt",
    "LocalCutoutErrors.kt",
    "LocalCutoutAsync.kt",
    "SoftMask.kt",
)

#: Every production Swift file under Runner/BackgroundRemoval must be a member of
#: the Runner target. The plugin is Flutter-linked, so the standalone RunnerTests
#: logic bundle deliberately excludes it -- and only it.
IOS_TEST_TARGET_EXCLUDED = frozenset({"WTMBackgroundRemovalPlugin.swift"})

#: The Swift suite must EXECUTE this many assertions, not merely exit zero. A run
#: that executes nothing is the exact failure this floor exists to catch.
MIN_SWIFT_TESTS = 91


@dataclass
class Check:
    name: str
    ok: bool
    detail: str

    @property
    def line(self) -> str:
        return f"  {'ok  ' if self.ok else 'FAIL'} {self.name}: {self.detail}"


@dataclass
class Report:
    checks: list[Check] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def add(self, name: str, ok: bool, detail: str) -> None:
        self.checks.append(Check(name, ok, detail))

    def require(self, name: str, ok: bool, ok_detail: str, fail_detail: str) -> bool:
        self.add(name, ok, ok_detail if ok else fail_detail)
        return ok

    @property
    def failures(self) -> list[Check]:
        return [c for c in self.checks if not c.ok]


# ── helpers ──────────────────────────────────────────────────────────────────
def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def strip_line_comments(source: str) -> str:
    """Remove `//` line comments and `/* */` blocks, so a check reads CODE.

    A comment explaining why an API is deliberately NOT called must not read as a
    call to it -- the check would then fire on the very file that documents the fix.
    """
    without_blocks = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return "\n".join(re.sub(r"//.*$", "", line) for line in without_blocks.splitlines())


def fingerprint(paths: Iterable[Path], root: Path) -> str:
    """Content hash of an ordered set of files, keyed by repo-relative path.

    Any edit to a native source, or to the compatibility manifest, changes this --
    which is how a recorded device result stops counting as evidence for code that
    is no longer the code that was tested.
    """
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda p: str(p).replace("\\", "/")):
        rel = path.relative_to(root).as_posix() if path.is_relative_to(root) else path.name
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes() if path.exists() else b"<missing>")
        digest.update(b"\0")
    return digest.hexdigest()[:16]


# ── shared configuration checks ──────────────────────────────────────────────
def check_gates(report: Report, config: dict[str, Any], expected: dict[str, str], where: str) -> None:
    """Assert the LITERAL gate values in the config the artifact was built from."""
    for gate, want in expected.items():
        raw = config.get(gate)
        if raw is None:
            report.add(f"gate {gate}", False, f"MISSING from {where} -- a missing gate compiles to false")
            continue
        if not isinstance(raw, str) or raw not in ("true", "false"):
            report.add(
                f"gate {gate}",
                False,
                f"{raw!r} is not the literal 'true' or 'false'; Dart compiles every other value to FALSE",
            )
            continue
        report.add(f"gate {gate}", raw == want, f"{raw}" if raw == want else f"{raw}, required {want}")


def check_policy_matches_config(report: Report, root: Path, profile: str, config: dict[str, Any]) -> None:
    """The generated config must equal the COMMITTED policy, gate for gate.

    This is what stops a CI env group, a hand-edited untracked file or a restored
    `.bak` from redefining which features a release contains.
    """
    policy_path = root / "app" / "env" / f"feature_policy.{profile}.json"
    policy = read_json(policy_path)
    if policy is None:
        report.add("committed feature policy", False, f"missing or unreadable: {policy_path.name}")
        return
    gates = policy.get("gates")
    if not isinstance(gates, dict) or not gates:
        report.add("committed feature policy", False, f"{policy_path.name} has no 'gates' object")
        return
    drift = {
        name: (config.get(name), want)
        for name, want in gates.items()
        if config.get(name) != want
    }
    report.require(
        "generated config matches committed policy",
        not drift,
        f"{policy_path.name}: {len(gates)} gate(s) agree",
        f"drift from {policy_path.name}: "
        + ", ".join(f"{k}={got!r} but policy says {want!r}" for k, (got, want) in sorted(drift.items())),
    )


# ── Android ──────────────────────────────────────────────────────────────────
def check_android(report: Report, root: Path, artifact: Path | None) -> None:
    android = root / "app" / "android" / "app"
    gradle = read_text(android / "build.gradle.kts")
    manifest = read_text(android / "src" / "main" / "AndroidManifest.xml")
    bg_dir = android / "src" / "main" / "kotlin" / "com" / "fashionos" / "app" / "background"
    main_activity = read_text(android / "src" / "main" / "kotlin" / "com" / "fashionos" / "app" / "MainActivity.kt")

    # Dependency present AND pinned. A dynamic version on a beta ML Kit client is a
    # silent-upgrade path into an unvalidated segmenter.
    match = re.search(
        rf'implementation\("{re.escape(MLKIT_ARTIFACT)}:([^"]+)"\)', gradle
    )
    if match is None:
        report.add("ML Kit dependency", False, f"{MLKIT_ARTIFACT} not declared in app/build.gradle.kts")
    else:
        version = match.group(1)
        dynamic = version.endswith("+") or version in ("latest.release", "latest.integration") or "$" in version
        report.add("ML Kit dependency", True, f"{MLKIT_ARTIFACT}:{version}")
        report.require(
            "ML Kit version pinned",
            not dynamic,
            f"exact version {version}",
            f"{version!r} is a dynamic version -- a beta segmenter must never float",
        )
        expected = expected_mlkit_from_manifest(root)
        if expected:
            report.require(
                "ML Kit version matches compatibility manifest",
                f"{MLKIT_ARTIFACT}:{version}" == expected,
                f"{version} == manifest",
                f"{version} but the compatibility manifest last validated {expected}",
            )

    report.require(
        "minSdk floor",
        re.search(r"minSdk\s*=\s*maxOf\(flutter\.minSdkVersion,\s*(\d+)\)", gradle) is not None
        and int(re.search(r"minSdk\s*=\s*maxOf\(flutter\.minSdkVersion,\s*(\d+)\)", gradle).group(1))
        >= ANDROID_MIN_SDK,
        f"minSdk >= {ANDROID_MIN_SDK} (ML Kit Subject Segmentation requires it)",
        f"minSdk is not pinned at or above {ANDROID_MIN_SDK}",
    )

    has_meta = re.search(
        rf'android:name="{re.escape(MLKIT_MANIFEST_KEY)}"\s*\n?\s*android:value="[^"]*{MLKIT_MANIFEST_VALUE}[^"]*"',
        manifest,
    )
    report.require(
        "install-time model metadata",
        has_meta is not None,
        f'{MLKIT_MANIFEST_KEY}="{MLKIT_MANIFEST_VALUE}" present',
        f"AndroidManifest.xml is missing the {MLKIT_MANIFEST_KEY}={MLKIT_MANIFEST_VALUE} metadata "
        "-- Play services then never pre-fetches the model and every first add falls back",
    )

    missing = [name for name in ANDROID_NATIVE_FILES if not (bg_dir / name).exists()]
    report.require(
        "native sources present",
        not missing,
        f"{len(ANDROID_NATIVE_FILES)} files under background/",
        f"missing native source(s): {', '.join(missing)}",
    )

    report.require(
        "plugin registered on the engine",
        "WtmBackgroundRemovalPlugin.register(" in main_activity
        and "configureFlutterEngine" in main_activity,
        "MainActivity.configureFlutterEngine() registers WtmBackgroundRemovalPlugin",
        "MainActivity does not register WtmBackgroundRemovalPlugin -- Dart would see "
        "MissingPluginException and silently use the cloud path",
    )
    report.require(
        "plugin detached on teardown",
        "cleanUpFlutterEngine" in main_activity and "backgroundRemoval?.detach()" in main_activity,
        "MainActivity.cleanUpFlutterEngine() detaches the plugin",
        "MainActivity does not detach the plugin in cleanUpFlutterEngine()",
    )

    plugin_src = read_text(bg_dir / "WtmBackgroundRemovalPlugin.kt")
    report.require(
        "Android channel name",
        f'CHANNEL = "{CHANNEL_NAME}"' in plugin_src,
        f'"{CHANNEL_NAME}" matches Dart',
        f"Kotlin channel constant does not equal Dart's {CHANNEL_NAME!r}",
    )
    report.require(
        "selfTest implemented (Android)",
        '"selfTest"' in plugin_src,
        "the selfTest method is handled",
        "WtmBackgroundRemovalPlugin does not handle 'selfTest' -- the native contract "
        "cannot be proven on a real device",
    )

    # ML Kit's full foreground confidence mask is corrupt on this SDK. It was proven
    # on hardware and cost a release; a future refactor must not quietly reinstate it.
    client_src = strip_line_comments(read_text(bg_dir / "MlKitSubjectSegmentationClient.kt"))
    report.require(
        "per-subject masks only",
        "enableForegroundConfidenceMask" not in client_src,
        "enableForegroundConfidenceMask() is not requested (it returns a corrupt buffer)",
        "enableForegroundConfidenceMask() is enabled -- measured 69% invalid on hardware",
    )

    minify_off = re.search(r"isMinifyEnabled\s*=\s*false", gradle) is not None
    keeps = read_text(android / "proguard-rules.pro")
    keeps_ok = "com.fashionos.app.background" in keeps or "com.google.mlkit" in keeps
    report.require(
        "release shrinking cannot strip the engine",
        minify_off or keeps_ok,
        "minification is off" if minify_off else "keep rules cover the engine + ML Kit",
        "R8 is enabled with no keep rule for com.fashionos.app.background / com.google.mlkit",
    )

    if artifact is not None:
        check_android_artifact(report, artifact)


def expected_mlkit_from_manifest(root: Path) -> str | None:
    manifest = read_json(root / "docs" / "bg" / "local_cutout_compatibility.json")
    if manifest is None:
        return None
    value = manifest.get("last_validated_mlkit_client")
    return value if isinstance(value, str) else None


def check_android_artifact(report: Report, artifact: Path) -> None:
    """Prove the SHIPPED bytes contain the engine, not just the source tree."""
    if not artifact.exists():
        report.add("artifact", False, f"{artifact} does not exist")
        return
    try:
        with zipfile.ZipFile(artifact) as archive:
            names = archive.namelist()
            manifest_blob = b""
            for candidate in ("base/manifest/AndroidManifest.xml", "AndroidManifest.xml"):
                if candidate in names:
                    manifest_blob = archive.read(candidate)
                    break
    except (OSError, zipfile.BadZipFile) as exc:
        report.add("artifact", False, f"{artifact.name} is not readable as a zip: {exc}")
        return

    # DEX is compiled, so class names survive as UTF-8 strings in the dex string pool
    # even though the .kt paths do not. Read them out of the dex members directly.
    blobs = b"".join(
        _safe_read(artifact, name) for name in names if name.endswith(".dex")
    )
    for symbol in ("WtmBackgroundRemovalPlugin", "GoogleSubjectSegmenterEngine"):
        report.require(
            f"artifact contains {symbol}",
            symbol.encode() in blobs,
            f"present in {artifact.name}",
            f"NOT present in {artifact.name} -- the engine was not compiled into the shipped artifact",
        )
    report.require(
        "artifact merged manifest metadata",
        MLKIT_MANIFEST_VALUE.encode() in manifest_blob,
        f"{MLKIT_MANIFEST_VALUE} survives into the merged manifest",
        f"the merged manifest in {artifact.name} has no {MLKIT_MANIFEST_VALUE} metadata",
    )


def _safe_read(archive_path: Path, name: str) -> bytes:
    try:
        with zipfile.ZipFile(archive_path) as archive:
            return archive.read(name)
    except (OSError, KeyError, zipfile.BadZipFile):
        return b""


# ── iOS ──────────────────────────────────────────────────────────────────────
def check_ios(report: Report, root: Path, artifact: Path | None, *, diagnostic: bool) -> None:
    ios = root / "app" / "ios"
    bg_dir = ios / "Runner" / "BackgroundRemoval"
    pbxproj = read_text(ios / "Runner.xcodeproj" / "project.pbxproj")
    app_delegate = read_text(ios / "Runner" / "AppDelegate.swift")

    sources = sorted(p.name for p in bg_dir.glob("*.swift")) if bg_dir.exists() else []
    report.require(
        "native sources present",
        bool(sources),
        f"{len(sources)} Swift files under Runner/BackgroundRemoval",
        "Runner/BackgroundRemoval contains no Swift sources",
    )

    runner_members = _pbx_target_sources(pbxproj, "Runner")
    tests_members = _pbx_target_sources(pbxproj, "RunnerTests")

    not_in_runner = [name for name in sources if name not in runner_members]
    report.require(
        "Runner target membership",
        not not_in_runner,
        f"all {len(sources)} sources compile into Runner",
        "NOT members of the Runner target (they would silently vanish from the app): "
        + ", ".join(not_in_runner),
    )

    # §3: the test bundle's source list is machine-checked against production rather
    # than being a duplicate that drifts. A test suite compiling different code than
    # the app is worse than no suite -- it reports confidence it has not earned.
    expected_tests = [n for n in sources if n not in IOS_TEST_TARGET_EXCLUDED]
    missing_from_tests = [n for n in expected_tests if n not in tests_members]
    report.require(
        "RunnerTests compiles the production sources",
        not missing_from_tests,
        f"{len(expected_tests)} production sources are also RunnerTests members",
        "RunnerTests does not compile: "
        + ", ".join(missing_from_tests)
        + " -- the Swift suite would be testing a different program than the one shipped",
    )

    report.require(
        "Flutter engine lifecycle",
        "FlutterImplicitEngineDelegate" in app_delegate
        and "didInitializeImplicitFlutterEngine" in app_delegate,
        "AppDelegate implements the current implicit-engine delegate",
        "AppDelegate does not implement FlutterImplicitEngineDelegate / "
        "didInitializeImplicitFlutterEngine -- registration would never run",
    )
    report.require(
        "GeneratedPluginRegistrant registered",
        "GeneratedPluginRegistrant.register(" in app_delegate,
        "pub plugins are registered",
        "AppDelegate never calls GeneratedPluginRegistrant.register",
    )
    report.require(
        "WTM plugin registered",
        "WTMBackgroundRemovalPlugin.register(" in app_delegate,
        "the local-cutout plugin is registered on the implicit engine",
        "AppDelegate never registers WTMBackgroundRemovalPlugin -- Dart would see "
        "MissingPluginException and silently use the cloud path",
    )
    report.require(
        "plugin detached on teardown",
        "backgroundRemoval?.detach()" in app_delegate,
        "AppDelegate detaches the plugin on terminate",
        "AppDelegate never detaches the plugin",
    )

    plugin_src = read_text(bg_dir / "WTMBackgroundRemovalPlugin.swift")
    report.require(
        "iOS channel name",
        f'channelName = "{CHANNEL_NAME}"' in plugin_src,
        f'"{CHANNEL_NAME}" matches Dart',
        f"Swift channel constant does not equal Dart's {CHANNEL_NAME!r}",
    )
    report.require(
        "selfTest implemented (iOS)",
        '"selfTest"' in plugin_src,
        "the selfTest method is handled",
        "WTMBackgroundRemovalPlugin does not handle 'selfTest'",
    )

    engine_src = read_text(bg_dir / "AppleVisionCutoutEngine.swift")
    report.require(
        "iOS 17 runtime gate with fallback below it",
        "@available(iOS 17.0, *)" in engine_src and "#available(iOS 17.0, *)" in engine_src,
        "Vision is guarded at runtime; older devices report unsupported and use the cloud",
        "the iOS 17 availability guard is missing -- either a crash below 17 or no fallback",
    )
    deployment = re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);", pbxproj)
    report.require(
        "deployment target below the Vision floor",
        bool(deployment) and all(float(v) < 17.0 for v in deployment),
        f"IPHONEOS_DEPLOYMENT_TARGET = {sorted(set(deployment))} -- pre-17 devices still install and fall back",
        f"deployment target {sorted(set(deployment))} would drop devices instead of falling back",
    )

    # The diagnostic export is a Swift compilation condition, injected only by the
    # internal workflow into the CI clone. Committing it would put an export sheet
    # and a changed fallback path in front of real users.
    release_xcconfig = read_text(ios / "Flutter" / "Release.xcconfig")
    condition_committed = "WTM_LOCAL_BG_DIAGNOSTICS" in release_xcconfig
    if diagnostic:
        report.require(
            "diagnostic compilation condition",
            condition_committed,
            "WTM_LOCAL_BG_DIAGNOSTICS is defined for this build",
            "WTM_LOCAL_BG_DIAGNOSTICS is not defined -- the export would be compiled out "
            "and the device session would produce nothing",
        )
    else:
        report.require(
            "no diagnostic condition in a store build",
            not condition_committed,
            "Release.xcconfig defines no WTM_LOCAL_BG_DIAGNOSTICS",
            "Release.xcconfig defines WTM_LOCAL_BG_DIAGNOSTICS -- an App Store build "
            "must never compile the diagnostic export in",
        )

    if artifact is not None:
        check_ios_artifact(report, artifact)


def _pbx_target_sources(pbxproj: str, target: str) -> set[str]:
    """File names in a target's Sources build phase, resolved through build files.

    Reads the real structure rather than grepping: a file reference can appear in
    the project navigator while belonging to no target at all, which is precisely
    the way a Swift source silently stops being compiled.
    """
    # Map buildFileId -> source file name, from the PBXBuildFile section.
    build_files: dict[str, str] = {
        m.group(1): m.group(2)
        for m in re.finditer(
            r"([0-9A-F]{24})\s*/\* (\S+\.swift) in Sources \*/ = \{isa = PBXBuildFile;", pbxproj
        )
    }
    # Find the native target, then its Sources phase id.
    target_match = re.search(
        r"/\* " + re.escape(target) + r" \*/ = \{\s*isa = PBXNativeTarget;(.*?)\n\t\t\};",
        pbxproj,
        re.DOTALL,
    )
    if target_match is None:
        return set()
    phase_ids = re.findall(r"([0-9A-F]{24}) /\* Sources \*/", target_match.group(1))
    names: set[str] = set()
    for phase_id in phase_ids:
        phase = re.search(
            re.escape(phase_id) + r" /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;(.*?)\n\t\t\};",
            pbxproj,
            re.DOTALL,
        )
        if phase is None:
            continue
        for build_file_id in re.findall(r"([0-9A-F]{24}) /\* \S+ in Sources \*/", phase.group(1)):
            name = build_files.get(build_file_id)
            if name:
                names.add(name)
    return names


def check_ios_artifact(report: Report, artifact: Path) -> None:
    """Prove the signed IPA/archive actually contains the compiled engine."""
    if not artifact.exists():
        report.add("artifact", False, f"{artifact} does not exist")
        return
    blob = b""
    if artifact.suffix == ".ipa":
        try:
            with zipfile.ZipFile(artifact) as archive:
                binaries = [
                    n
                    for n in archive.namelist()
                    if re.match(r"Payload/[^/]+\.app/[^/.]+$", n)
                ]
                blob = b"".join(archive.read(n) for n in binaries)
        except (OSError, zipfile.BadZipFile) as exc:
            report.add("artifact", False, f"{artifact.name} is not readable: {exc}")
            return
    else:
        candidates = list(artifact.glob("Products/Applications/*.app/*"))
        blob = b"".join(p.read_bytes() for p in candidates if p.is_file() and not p.suffix)

    for symbol in (b"WTMBackgroundRemovalPlugin", b"AppleVisionCutoutEngine"):
        report.require(
            f"artifact contains {symbol.decode()}",
            symbol in blob,
            f"symbol present in {artifact.name}",
            f"symbol NOT present in {artifact.name} -- the engine is not in the shipped binary",
        )
    report.require(
        "no diagnostic exporter in the artifact",
        b"exportDiagnostics" not in blob or b"WTM_LOCAL_BG_DIAGNOSTICS" not in blob,
        "the diagnostic export is compiled out",
        "the artifact carries the diagnostic export",
    )


# ── backend ──────────────────────────────────────────────────────────────────
def check_backend(report: Report, root: Path, env: dict[str, str]) -> None:
    backend = root / "backend" / "app"
    wardrobe = read_text(backend / "routers" / "v1" / "wardrobe.py")
    config = read_text(backend / "core" / "config.py")
    mask_ingest = read_text(backend / "services" / "bg" / "mask_ingest.py")
    imaging = read_text(backend / "services" / "bg" / "imaging.py")

    report.require(
        "local-cutout endpoint exists",
        '@router.post("/wardrobe/local-cutout"' in wardrobe,
        "POST /v1/wardrobe/local-cutout is routed",
        "the local-cutout endpoint is gone -- every device would fall back to the worker",
    )
    report.require(
        "production gate is enforced at startup",
        "LOCAL_CUTOUT_UPLOAD_ENABLED" in config and "_REQUIRED_PROD_GATES" in config,
        "config.py refuses to start prod without an explicit gate",
        "config.py no longer requires LOCAL_CUTOUT_UPLOAD_ENABLED in production",
    )
    report.require(
        "explicit false is refused in production",
        "local_cutout_emergency_disable" in config,
        "an explicit false is a startup failure unless the emergency switch is set",
        "config.py accepts LOCAL_CUTOUT_UPLOAD_ENABLED=false in prod -- a complete "
        "local-first outage with a healthy /healthz and nothing in the logs",
    )

    upload = env.get("LOCAL_CUTOUT_UPLOAD_ENABLED")
    if upload is None:
        report.add(
            "LOCAL_CUTOUT_UPLOAD_ENABLED",
            False,
            "not set in the environment being verified -- pass --backend-env-file or export it",
        )
    else:
        report.require(
            "LOCAL_CUTOUT_UPLOAD_ENABLED",
            upload.strip().lower() == "true",
            "true",
            f"{upload!r} -- the ingestion endpoint answers 404 and every user silently "
            "reverts to the cloud worker",
        )
    emergency = (env.get("LOCAL_CUTOUT_EMERGENCY_DISABLE") or "false").strip().lower()
    report.require(
        "LOCAL_CUTOUT_EMERGENCY_DISABLE",
        emergency == "false",
        "false (normal operation)",
        f"{emergency!r} -- the emergency kill-switch is engaged; local-first removal is OFF "
        "for every user. This must be a deliberate, time-boxed incident state.",
    )

    report.require(
        "alpha-bearing output",
        "compose_cutout_webp" in mask_ingest and "lossless=True" in imaging,
        "the composed cutout is lossless WebP with a real alpha channel",
        "the cutout is no longer composed losslessly with alpha -- a flattened cutout "
        "renders as an opaque rectangle in the closet",
    )
    report.require(
        "declared MIME matches the bytes",
        'cutout_content_type="image/webp"' in mask_ingest
        and "content_type=composed.cutout_content_type" in wardrobe,
        "image/webp travels with the WebP bytes",
        "the stored content type is hardcoded away from the encoder's own -- the CDN "
        "would serve a WebP labelled PNG",
    )
    report.require(
        "mask validated against the stored original",
        "_ingest_local_mask" in wardrobe and "bg_max_image_edge" in wardrobe,
        "dimensions and edge caps are re-derived server-side",
        "the server no longer re-validates the uploaded mask against the stored original",
    )


# ── device evidence (§8, §9) ─────────────────────────────────────────────────
def native_fingerprint(root: Path, platform: str) -> str:
    manifest = root / "docs" / "bg" / "local_cutout_compatibility.json"
    if platform == "android":
        base = root / "app" / "android" / "app" / "src" / "main" / "kotlin" / "com" / "fashionos" / "app"
        files = sorted((base / "background").glob("*.kt")) + [base / "MainActivity.kt"]
    else:
        base = root / "app" / "ios" / "Runner"
        files = sorted((base / "BackgroundRemoval").glob("*.swift")) + [base / "AppDelegate.swift"]
    return fingerprint([*files, manifest], root)


def check_device_evidence(report: Report, root: Path, platform: str) -> None:
    """A release may not ship native code that has never run on real hardware.

    Compilation is not validation, and a mocked unit test is not a device. The
    recorded evidence is keyed by a fingerprint of the native sources plus the
    compatibility manifest, so touching either -- an engine change, an SDK bump, a
    Flutter upgrade -- invalidates it and forces the matrix to run again.
    """
    path = root / "docs" / "bg" / "local_cutout_device_evidence.json"
    document = read_json(path)
    if document is None:
        report.add("device evidence", False, f"{path.name} is missing or unreadable")
        return
    current = native_fingerprint(root, platform)
    entries = document.get(platform)
    entries = entries if isinstance(entries, list) else []
    matching = [e for e in entries if isinstance(e, dict) and e.get("native_fingerprint") == current]
    passing = [e for e in matching if e.get("result") == "pass"]

    manifest = read_json(root / "docs" / "bg" / "local_cutout_compatibility.json") or {}
    key = f"minimum_{platform}_device_test_count"
    minimum = manifest.get(key)
    minimum = minimum if isinstance(minimum, int) and minimum > 0 else 1

    if not matching:
        report.add(
            "device evidence",
            False,
            f"no recorded {platform} device run matches the current native code "
            f"(fingerprint {current}). Run the device matrix and record it in {path.name}; "
            "compilation and mocked tests are not device validation.",
        )
        return
    report.require(
        "device evidence",
        len(passing) >= minimum,
        f"{len(passing)} passing {platform} device run(s) at fingerprint {current} (>= {minimum})",
        f"only {len(passing)} passing {platform} device run(s) at fingerprint {current}, "
        f"{minimum} required",
    )


# ── Swift test-count assertion (§8) ──────────────────────────────────────────
def check_swift_test_log(report: Report, log_path: Path) -> None:
    """A Swift suite that exits zero after executing NOTHING must fail the build."""
    text = read_text(log_path)
    if not text:
        report.add("Swift suite", False, f"{log_path} is missing or empty -- the suite did not run")
        return
    # MAX, not sum. xcodebuild prints "Executed N tests" once per suite AND twice
    # more for the aggregates, so summing counted 129 real tests as 387. That is not
    # merely a cosmetic overcount: it inflates every run against the floor, so a
    # partial run of one 45-test suite would report 135 and clear a minimum of 91.
    # The largest figure is the aggregate, which is the number this gate is about.
    counts = [int(m) for m in re.findall(r"Executed (\d+) tests?", text)]
    executed = max(counts) if counts else 0
    failures = max(
        (int(m) for m in re.findall(r"Executed \d+ tests?, with (\d+) failures?", text)),
        default=0,
    )
    report.require(
        "Swift tests executed",
        executed >= MIN_SWIFT_TESTS,
        f"{executed} executed (>= {MIN_SWIFT_TESTS})",
        f"only {executed} executed, expected at least {MIN_SWIFT_TESTS} -- a suite that "
        "runs zero tests exits successfully and proves nothing",
    )
    report.require(
        "Swift tests passed",
        failures == 0,
        "0 failures",
        f"{failures} failure(s)",
    )


# ── environment sources ──────────────────────────────────────────────────────
def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in read_text(path).splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.split("#", 1)[0].strip().strip('"').strip("'")
    return values


def git_sha(root: Path) -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short=8", "HEAD"],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        return out.stdout.strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


# ── targets ──────────────────────────────────────────────────────────────────
TargetFn = Callable[[Report, argparse.Namespace, Path], None]


def target_android_production(report: Report, args: argparse.Namespace, root: Path) -> None:
    config = read_json(Path(args.config)) or {}
    check_gates(report, config, {k: v for k, v in PRODUCTION_GATES.items() if k != "LOCAL_BG_IOS_ENABLED"}, args.config)
    check_policy_matches_config(report, root, "prod", config)
    check_android(report, root, Path(args.artifact) if args.artifact else None)
    if not args.skip_device_evidence:
        check_device_evidence(report, root, "android")


def target_ios_production(report: Report, args: argparse.Namespace, root: Path) -> None:
    config = read_json(Path(args.config)) or {}
    check_gates(report, config, PRODUCTION_GATES, args.config)
    check_policy_matches_config(report, root, "prod", config)
    check_ios(report, root, Path(args.artifact) if args.artifact else None, diagnostic=False)
    if args.swift_test_log:
        check_swift_test_log(report, Path(args.swift_test_log))
    if not args.skip_device_evidence:
        check_device_evidence(report, root, "ios")


def target_ios_diagnostic(report: Report, args: argparse.Namespace, root: Path) -> None:
    config = read_json(Path(args.config)) or {}
    check_gates(report, config, DIAGNOSTIC_GATES, args.config)
    check_policy_matches_config(report, root, "ios-diagnostic", config)
    check_ios(report, root, Path(args.artifact) if args.artifact else None, diagnostic=True)
    report.notes.append(
        "INTERNAL DIAGNOSTIC BUILD. This is not production validation: diagnostics are "
        "compiled in and the local failure path is deliberately surfaced."
    )


def target_ci(report: Report, args: argparse.Namespace, root: Path) -> None:
    """Structure-only pass for every PR: no generated config, no artifact, no device.

    Deliberately cheap and deliberately not a release gate -- it catches the native
    file, registration, channel-name and endpoint regressions at review time.
    """
    for profile in ("prod", "ios-diagnostic"):
        policy = read_json(root / "app" / "env" / f"feature_policy.{profile}.json")
        report.require(
            f"committed policy ({profile})",
            policy is not None and isinstance(policy.get("gates"), dict),
            "present and well-formed",
            f"feature_policy.{profile}.json is missing or has no gates",
        )
    prod_policy = read_json(root / "app" / "env" / "feature_policy.prod.json") or {}
    check_gates(report, prod_policy.get("gates") or {}, PRODUCTION_GATES, "feature_policy.prod.json")
    check_android(report, root, None)
    check_ios(report, root, None, diagnostic=False)
    check_backend(report, root, {"LOCAL_CUTOUT_UPLOAD_ENABLED": "true"})
    report.notes.append(
        "CI structure pass. Device evidence and artifact inspection are release-time checks."
    )


def target_backend(report: Report, args: argparse.Namespace, root: Path) -> None:
    env = dict(os.environ)
    if args.backend_env_file:
        env.update(load_env_file(Path(args.backend_env_file)))
    check_backend(report, root, env)


TARGETS: dict[str, TargetFn] = {
    "android-production": target_android_production,
    "ios-production": target_ios_production,
    "ios-diagnostic": target_ios_diagnostic,
    "backend": target_backend,
    "ci": target_ci,
}


def record_device_evidence(root: Path, platform: str, fields: dict[str, str]) -> int:
    """Append a device-session result, computing the fingerprint rather than trusting one.

    The hash is derived here, from the working tree, so an entry can only ever
    describe the code that was actually present when the session ran.
    """
    path = root / "docs" / "bg" / "local_cutout_device_evidence.json"
    document = read_json(path)
    if document is None:
        print(f"FATAL: {path} is missing or unreadable", file=sys.stderr)
        return 1
    entry: dict[str, Any] = {
        "recorded": fields.get("recorded", ""),
        "commit": git_sha(root),
        "app_version": fields.get("app_version", ""),
        "native_fingerprint": native_fingerprint(root, platform),
        "result": fields.get("result", "pass"),
        "runs": int(fields.get("runs", "1")),
        "engine": "google_mlkit" if platform == "android" else "apple_vision",
        "notes": fields.get("notes", ""),
    }
    entries = document.get(platform)
    document[platform] = [*entries, entry] if isinstance(entries, list) else [entry]
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"recorded {platform} device evidence at fingerprint {entry['native_fingerprint']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", choices=sorted(TARGETS))
    parser.add_argument(
        "--record-device-evidence",
        choices=("android", "ios"),
        default=None,
        help="append a passing/failing device-session result for this platform and exit",
    )
    parser.add_argument("--recorded", default="", help="date of the device session (YYYY-MM-DD)")
    parser.add_argument("--app-version", default="", help="version+build tested on the device")
    parser.add_argument("--runs", default="1", help="how many real cutouts were performed")
    parser.add_argument("--result", default="pass", choices=("pass", "fail"))
    parser.add_argument("--notes", default="", help="what was observed, in plain words")
    parser.add_argument("--print-fingerprint", choices=("android", "ios"), default=None)
    parser.add_argument("--repo-root", default=str(DEFAULT_REPO_ROOT))
    parser.add_argument("--config", default=None, help="generated dart-define JSON (default app/env/prod.json)")
    parser.add_argument("--artifact", default=None, help="APK/AAB/IPA/xcarchive to inspect")
    parser.add_argument("--backend-env-file", default=None)
    parser.add_argument("--swift-test-log", default=None)
    parser.add_argument(
        "--skip-device-evidence",
        action="store_true",
        help="omit the physical-device requirement (dry runs and negative tests only)",
    )
    parser.add_argument(
        "--pre-device-validation",
        action="store_true",
        help=(
            "produce a signed artifact FOR the device matrix. Every structural invariant "
            "still blocks; only the device-evidence requirement is reported as an outstanding "
            "warning, because the build has to exist before anyone can run it on hardware."
        ),
    )
    parser.add_argument("--warn-only", action="store_true", help="report without failing the build")
    args = parser.parse_args(argv)

    root = Path(args.repo_root).resolve()
    if args.config is None:
        args.config = str(root / "app" / "env" / "prod.json")

    if args.print_fingerprint:
        print(native_fingerprint(root, args.print_fingerprint))
        return 0
    if args.record_device_evidence:
        return record_device_evidence(
            root,
            args.record_device_evidence,
            {
                "recorded": args.recorded,
                "app_version": args.app_version,
                "runs": args.runs,
                "result": args.result,
                "notes": args.notes,
            },
        )
    if not args.target:
        parser.error("--target is required unless --record-device-evidence or --print-fingerprint is used")

    report = Report()
    print(f"local-cutout release verification -- target={args.target} sha={git_sha(root)}")
    TARGETS[args.target](report, args, root)

    for check in report.checks:
        print(check.line)
    for note in report.notes:
        print(f"  note {note}")

    failures = report.failures
    # A signed artifact must exist before it can be run on a phone, so refusing to
    # BUILD until device evidence exists is circular. This mode names that state
    # rather than leaving people to reach for --warn-only, which would suppress
    # every other invariant too. Only the device check is downgraded; a missing
    # gate, an unregistered plugin or a dropped source file still stops the build.
    outstanding: list[Check] = []
    if args.pre_device_validation:
        outstanding = [c for c in failures if c.name == "device evidence"]
        failures = [c for c in failures if c.name != "device evidence"]

    if failures:
        print(
            f"\n{len(failures)} INVARIANT(S) VIOLATED -- this build must not ship:",
            file=sys.stderr,
        )
        for check in failures:
            print(f"  * {check.name}: {check.detail}", file=sys.stderr)
        if not args.warn_only:
            return 2
        print("(--warn-only: not failing)", file=sys.stderr)
        return 0

    if outstanding:
        print("\n" + "!" * 78)
        print("PRE-DEVICE-VALIDATION BUILD -- NOT RELEASE APPROVED.")
        print("Every structural invariant holds, and this artifact is correctly signed and")
        print("configured. It is NOT cleared for Google Play or the App Store, because:")
        for check in outstanding:
            print(f"  * {check.detail}")
        print("")
        print("Install it, run the device matrix in docs/bg/LOCAL_FIRST_BG_OPERATIONS.md §6,")
        print("then record the result with --record-device-evidence and re-run this verifier")
        print("with no flags. Only a clean run with no flags clears a release.")
        print("!" * 78)
        return 0

    print(f"\nAll {len(report.checks)} invariants hold.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

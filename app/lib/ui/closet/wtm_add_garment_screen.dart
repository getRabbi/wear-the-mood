import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/env/app_env.dart';
import '../../core/media/image_pick_permission.dart';
import '../../core/media/media_upload_service.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/ai_job.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/wardrobe/closet_category.dart';
import '../../features/wardrobe/local_cutout/local_cutout_analytics.dart';
import '../../features/wardrobe/local_cutout/local_cutout_health.dart';
import '../../features/wardrobe/local_cutout/local_cutout_models.dart';
import '../../features/wardrobe/local_cutout/local_cutout_orchestrator.dart';
import '../../features/wardrobe/local_cutout/local_cutout_providers.dart';
import '../../features/wardrobe/wardrobe_image_service.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_enhance.dart';

/// Add Garment (§3.10, P3) — the REAL pipeline in Atelier dress:
/// camera/gallery pick (compressed, EXIF-stripped) → upload → **background
/// removal** (on-device engine, else a cloud `cutout_temp` job) → **look at the
/// cutout** → name + category, both mandatory → Save → the garment is created →
/// closet refresh → toast.
///
/// The order matters and was got wrong twice.
///
/// Originally the item was created FIRST, because the cloud remover's work queue
/// IS the wardrobe table — a cutout could not exist without a garment to hang it
/// on. When the API began requiring a name and a category on every manual
/// create, that create (issued at the end of a removal that had just succeeded)
/// started coming back 422, and the user was shown a background-removal failure
/// whose Try again re-ran the removal and failed identically.
///
/// The first fix moved the metadata question BEFORE the removal. It worked, but
/// it bent the product around a queue implementation detail: it made people name
/// a garment they had not yet seen.
///
/// `cutout_temp` (0071) removed the constraint instead. A removal can now finish
/// with nowhere to live, so this screen shows the result and asks what the piece
/// is afterwards — and **nothing reaches the closet until Save**. A user who
/// backs out at any earlier point leaves no trace, and the piece that is finally
/// created carries its name, its category and the cutout they approved.
///
/// Mobile-QA restore: the shipped composer's add-mode choice rides along —
/// free "Remove background" (default) vs the premium **AI Enhance**
/// (Pro/Pro Max, spends credits via `/v1/ai/enhance`, §18 confirm-before-
/// charge). Free users see it locked → paywall. "Enhance item" and "Fix cutout"
/// are NOT offered here any more: both act on a garment, and at the point they
/// used to appear no garment exists yet. Both live on the garment detail screen.
class WtmAddGarmentScreen extends ConsumerStatefulWidget {
  const WtmAddGarmentScreen({super.key});

  @override
  ConsumerState<WtmAddGarmentScreen> createState() =>
      _WtmAddGarmentScreenState();
}

enum _Stage { capture, processing, confirm, failed }

/// Bounds on the two garment previews.
///
/// Both used to be fixed rectangles — a 300dp-tall band while the removal ran,
/// and a 200dp-wide 3:4 tile afterwards — so a tall garment (trousers, a maxi
/// dress) and a wide one (a coat laid flat) were forced through the same hole
/// and both came out deformed or letterboxed. They are aspect-derived now, and
/// these bounds keep that from costing the screen its shape.
///
/// The ceilings are deliberately TIGHT, and the reason is specific to a cutout:
/// a background-removed PNG keeps the ORIGINAL photo's canvas, so most of it is
/// transparent and its intrinsic ratio describes the photo, not the garment. On
/// device that showed up exactly as it sounds — a 340dp-tall slot holding a
/// 211dp garment with 123dp of empty space above it, pushing the name field and
/// the category chips down the screen. Shrinking the slot shrinks the dead
/// margin with it, so the piece reads as a tidy object on a card rather than as
/// a poster.
///
/// Still `BoxFit.contain` inside these: a cutout must never be cropped, or the
/// user is judging a sleeve or a hem that was cut off by the frame rather than
/// by the removal.
const _previewMinHeight = 180.0;
const _previewMaxHeight = 280.0;
const _confirmPreviewMaxWidth = 220.0;
const _confirmPreviewMinHeight = 150.0;
const _confirmPreviewMaxHeight = 240.0;

/// A finished background removal that has no garment yet.
///
/// This is what makes the intended order possible: the removal runs, its result
/// is shown, and only then is the user asked what the piece is. Nothing here has
/// been saved — the closet is untouched until Save.
class _PreparedCutout {
  const _PreparedCutout({
    required this.media,
    this.local,
    this.localCutoutPath,
    this.cutoutJobId,
    this.cutoutUrl,
  });

  /// The uploaded original. Always present — it is what the create is built on.
  final MediaRef media;

  /// The on-device result, when the local engine produced one. Carries the mask
  /// the server re-composites from, plus the engine identity for telemetry.
  final LocalCutoutAccepted? local;

  /// The on-device cutout file to preview.
  final String? localCutoutPath;

  /// The cloud `cutout_temp` job that produced [cutoutUrl], adopted at save time
  /// so the worker is never asked to redo it.
  final String? cutoutJobId;

  /// The cloud cutout to preview (a signed, short-lived URL).
  final String? cutoutUrl;

  /// Whether a background-removed image actually exists to show.
  ///
  /// False only in the degraded case where neither engine could produce one and
  /// the piece will be cut server-side after it is saved — the copy says so
  /// rather than implying the original IS the cutout.
  bool get hasCutout => localCutoutPath != null || cutoutUrl != null;
}

/// Raised when there is no usable stored original, so the cloud path cannot help
/// either and the user must pick the photo again (local BG §6.3). Private and
/// caught in `_run`; never surfaced as an exception to the user.
class _ReselectRequired implements Exception {
  const _ReselectRequired();
}

/// Raised when the background removal itself could not produce anything and the
/// piece cannot be added from this photo. Terminal for this attempt; the user
/// retries or picks another image.
class _RemovalFailed implements Exception {
  const _RemovalFailed(this.message);
  final String message;
}

class _WtmAddGarmentScreenState extends ConsumerState<WtmAddGarmentScreen>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.capture;
  Uint8List? _bytes;
  String? _error;
  bool _saving = false;
  bool _picking =
      false; // a picker is open — a second tap must not open another
  bool _running = false; // `_run` is in flight — see the re-entrancy note there
  bool _enhance = false; // AI Enhance mode picked on capture

  /// Whether the required-field errors are showing. Held back until the user has
  /// actually tried to continue, so an untouched form does not greet them in red.
  bool _showMetadataErrors = false;
  bool _enhancePhase = false; // poll is past bg-removal, enhance running
  String? _enhanceError; // the enhance JOB failed — shown on the confirm stage
  final _name = TextEditingController();
  ClosetCategory? _category;

  /// Drives the "alive" cutout wait: status steps through warming → clearing →
  /// refining → almost by elapsed time (the Job reports no sub-progress) and a
  /// tip rotates so the ~90s cold start never feels frozen.
  DateTime? _procStartedAt;
  Timer? _cycle;

  /// The finished removal, waiting to be named. Set when processing succeeds and
  /// consumed by [_save]; while it is non-null the closet still knows nothing
  /// about this piece.
  _PreparedCutout? _prepared;

  /// The mask, pushed to storage while the user is still naming the piece.
  ///
  /// Save used to be the moment this upload STARTED, so most of the wait between
  /// tapping Save and the closet appearing was the mask going up a phone's
  /// uplink. Staging it here spends that time while the user types instead.
  ///
  /// This writes no closet row — an object with no row is not a garment — so the
  /// promise that backing out before Save leaves no trace still holds.
  ///
  /// Best-effort by design: a null result (staging unfinished, R2 gate off, or a
  /// failed PUT) simply means [_createItem] sends the bytes inline exactly as it
  /// did before, so a bad upload can never cost the user their save.
  Future<String?>? _stagedMask;

  // ── local-first background removal (dormant unless the gates are on) ──────
  /// The on-device cutout, once the engine has written it. Shown immediately as a
  /// preview while the save is still in flight — the copy says so.
  String? _localCutoutPath;

  /// The operation whose scratch files we own and must delete on every exit path.
  String? _localOperationId;

  /// True once the local cutout exists and we are only waiting on the server.
  bool _localSaving = false;

  /// True while this add is on the local-first path, so the copy stays honest even
  /// before the engine has produced a file.
  bool _isLocalAttempt = false;

  /// True while we are waiting on the on-device engine to become available —
  /// on a fresh Android install that is Play services fetching the segmentation
  /// model, which is a real wait and deserves its own honest copy.
  bool _preparingTools = false;

  /// Guards the lost-capture recovery so a rebuild or a second resume can never
  /// process the same recovered photo twice.
  bool _recoveringLostCapture = false;

  /// Cached so `dispose()` can clean up WITHOUT touching `ref` — Riverpod forbids
  /// reading a provider from a widget that is being unmounted, and the scratch
  /// files still have to go. Resolved on first use, never in dispose.
  LocalCutoutOrchestrator? _orchestrator;

  /// Resolve the orchestrator once and remember it. Safe to call any time the
  /// widget is still mounted; `dispose()` reads the cached field instead.
  LocalCutoutOrchestrator get _localCutout {
    final cached = _orchestrator;
    if (cached != null) return cached;
    final resolved = ref.read(localCutoutOrchestratorProvider);
    _orchestrator = resolved;
    return resolved;
  }

  // The closet poll that used to live here is gone with the create-first order:
  // a locally cut piece is born `done`, and a cloud cut is waited for as a JOB
  // (`pollWtmAiJob`) before any garment exists. Nothing is left to poll the
  // wardrobe list for.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A capture can already be waiting when this screen first builds: Android
    // rebuilt the process while the camera was in front, so the photo exists
    // but our old activity never received it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostCapture());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the camera is a resume. If Android dropped the result on
    // the way, this is where it is handed over.
    if (state == AppLifecycleState.resumed) _recoverLostCapture();
  }

  /// Pick up a capture Android threw away, and continue as if it had arrived
  /// normally. Only while the screen is still waiting for a photo — never on top
  /// of an add that is already processing or confirming.
  Future<void> _recoverLostCapture() async {
    if (_recoveringLostCapture) return;
    if (_stage != _Stage.capture || _bytes != null) return;
    _recoveringLostCapture = true;
    try {
      final bytes = await ref
          .read(wardrobeImageServiceProvider)
          .recoverLostCapture();
      if (bytes == null || !mounted) return;
      // Re-check: the user may have picked a new photo while we were asking.
      if (_stage != _Stage.capture || _bytes != null) return;
      _bytes = bytes;
      _run();
    } on Object {
      // Strictly best-effort. Recovery runs unprompted, before the user has
      // done anything, so a failure here must leave the capture screen exactly
      // as it was — never an error aimed at someone who just opened it.
    } finally {
      _recoveringLostCapture = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cycle?.cancel();
    // The on-device cutout files are ours. Take them with us on back/cancel or any
    // other disposal — read the provider from the container BEFORE super.dispose(),
    // and fire-and-forget because dispose cannot await (§9.1.8).
    final operationId = _localOperationId;
    final orchestrator = _orchestrator;
    if (operationId != null && orchestrator != null) {
      _localOperationId = null;
      orchestrator.cancel(operationId);
      unawaited(orchestrator.discard(operationId));
    }
    _name.dispose();
    super.dispose();
  }

  /// Elapsed-time → friendly stage text for the BG-removal wait.
  String _stageText(AppLocalizations l10n) {
    // Say what is actually happening. On a fresh install the engine may still
    // be arriving, and calling that "clearing the background" would be a
    // progress message for work that has not started.
    if (_preparingTools) return l10n.wtmAddPreparingTools;
    final s = DateTime.now()
        .difference(_procStartedAt ?? DateTime.now())
        .inSeconds;
    if (s < 12) return l10n.wardrobeStageWarming;
    if (s < 40) return l10n.wardrobeStageClearing;
    if (s < 70) return l10n.wardrobeStageRefining;
    return l10n.wardrobeStageAlmost;
  }

  /// A tip that rotates every ~8s so the wait stays engaging.
  String _tip(AppLocalizations l10n) {
    final tips = [
      l10n.wardrobeTipBatch,
      l10n.wardrobeTipTryOn,
      l10n.wardrobeTipQuality,
    ];
    final i =
        DateTime.now().difference(_procStartedAt ?? DateTime.now()).inSeconds ~/
        8;
    return tips[i % tips.length];
  }

  Future<void> _pick(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    // The confirm sheet and the picker are both awaits, and the CTA stays mounted
    // across them — without this a second tap opens a second picker, and two
    // photos racing through the same state is how one add becomes two items.
    if (_picking) return;
    setState(() => _picking = true);
    try {
      if (_enhance && !await confirmWtmEnhanceSpend(context, ref)) return;
      if (!mounted) return;
      Uint8List? bytes;
      try {
        bytes = await ref
            .read(wardrobeImageServiceProvider)
            .pickAndCompress(source);
      } catch (e) {
        if (!mounted) return;
        if (isImagePermissionDenied(e)) {
          await showImagePermissionHelp(
            context,
            camera: source == ImageSource.camera,
          );
        } else {
          wtmSnack(context, l10n.wtmAddPickFailed);
        }
        return;
      }
      if (bytes == null || !mounted) return; // user cancelled the picker
      _bytes = bytes;
      _run();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Both mandatory fields are present. Checked before the API is asked, and
  /// again by the API itself — a client is not a validation layer (§13).
  bool get _metadataComplete =>
      _name.text.trim().isNotEmpty && _category != null;

  /// Run the on-device cutout once the engine is ready, saying so if the wait is
  /// visible. Never throws — every failure is a typed rejection that routes to
  /// the existing cloud path exactly as before.
  Future<LocalCutoutAttempt> _attemptLocal(
    LocalCutoutOrchestrator orchestrator,
  ) async {
    if (!orchestrator.isReady) {
      // On a fresh install this is a real wait (Play services fetching the
      // segmentation model), so name it rather than leaving the generic
      // "warming" copy to imply the render itself has started.
      if (mounted) setState(() => _preparingTools = true);
      await orchestrator.ensureReady();
      if (!mounted) {
        return const LocalCutoutRejected(LocalCutoutFallbackReason.cancelled);
      }
      setState(() => _preparingTools = false);
    }
    return orchestrator.attemptWhenReady(_bytes!);
  }

  Future<void> _run() async {
    // Re-entrancy guard. Every add uploads a FRESH original, and the local
    // endpoint's idempotency is keyed on that object key — so two overlapping
    // runs are two keys and two items, which no server-side dedupe can catch.
    // Reachable from a double-tapped Continue and from the retry CTA.
    if (_running) return;
    _running = true;
    try {
      await _runOnce();
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce() async {
    final l10n = AppLocalizations.of(context);
    final orchestrator = _localCutout;
    final localEnabled = orchestrator.isEnabledForThisBuild;
    setState(() {
      _prepared = null;
      _stage = _Stage.processing;
      _enhancePhase = false;
      _enhanceError = null;
      _error = null;
      _isLocalAttempt = localEnabled;
      _localSaving = false;
      _localCutoutPath = null;
    });
    _procStartedAt = DateTime.now();
    // Repaint every few seconds so the staged status + rotating tip advance.
    _cycle ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _stage == _Stage.processing) setState(() {});
    });
    try {
      // Upload and local removal run CONCURRENTLY: the upload is network-bound and
      // the engine is CPU-bound, so overlapping them is what makes the preview feel
      // instant. Both consume the SAME bytes — the engine must segment exactly what
      // gets stored as the original (§8.1).
      final uploadFuture = ref
          .read(wardrobeImageServiceProvider)
          .upload(_bytes!);
      // attemptWhenReady, not attempt: it waits for the SHARED preparation
      // started at launch instead of racing it, and retries the on-device
      // analysis once if the engine came up late. The upload above is a
      // separate future, so that retry can never duplicate an upload, a job or
      // a charge.
      final localFuture = orchestrator.isEnabledForThisBuild
          ? _attemptLocal(orchestrator)
          : Future<LocalCutoutAttempt>.value(
              const LocalCutoutRejected(LocalCutoutFallbackReason.gateDisabled),
            );

      final local = await localFuture;
      if (!mounted) {
        // Disposed mid-flight: the files are ours, so take them with us.
        if (local is LocalCutoutAccepted) {
          await orchestrator.discard(local.result.operationId);
        }
        return;
      }
      // Safe, bucketed observability (§10). Fired once per add, and never with
      // bytes, paths, keys, exact dimensions or exception text.
      _trackLocalOutcome(local);
      // And once with the full build/engine context, on EVERY path (§6) — that is
      // the series the release alerts read.
      _trackOperation(local, cloudFallbackUsed: local is! LocalCutoutAccepted);

      // INTERNAL DIAGNOSTIC BUILDS ONLY (iOS Phase 3). A local failure is normally
      // invisible by design: it becomes a quiet cloud fallback and the tester learns
      // nothing, which is exactly how iOS could ship an encoder that never worked.
      // Here the failure is surfaced and its preserved evidence offered for export
      // BEFORE the cloud path continues. `hasExportableDiagnostics` is only ever
      // true when the diagnostics gate is compiled in, so this is unreachable in
      // production and invisible on Android.
      if (local is LocalCutoutRejected && local.hasExportableDiagnostics) {
        final proceed = await _surfaceLocalDiagnosticFailure(
          local,
          orchestrator,
        );
        // The evidence has served its purpose either way; leaving it would grow the
        // cache across a 20-run session.
        await orchestrator.discard(local.diagnosticOperationId);
        if (!mounted) return;
        if (!proceed) {
          await _discardLocal();
          _fail(
            'Local cutout failed: ${local.reason.name}. Cloud path declined.',
          );
          return;
        }
      }

      if (local is LocalCutoutAccepted) {
        // Reveal the on-device cutout the moment the engine writes it.
        setState(() {
          _localOperationId = local.result.operationId;
          _localCutoutPath = local.result.cutoutFilePath;
        });
      }

      final media = await uploadFuture;
      if (!mounted) {
        await _discardLocal();
        return;
      }
      // No usable original means the cloud remover has nothing either — asking
      // the user to reselect beats promising a cutout that cannot be made.
      final noSource =
          media.objectKey == null && media.legacyUrl == null ||
          (local is LocalCutoutRejected && !local.canUseCloudFallback);
      if (noSource) {
        await _discardLocal();
        _fail(l10n.wtmAddReselectPhoto);
        return;
      }

      // THE ordering fix. Processing ends with a cutout, not with a garment: the
      // user sees the result and is asked what the piece is afterwards, and
      // nothing reaches the closet until they save. The old flow had to create
      // the item here purely because the cloud remover's queue IS the wardrobe
      // table — so a cutout could not exist without a garment to hang it on.
      // `cutout_temp` (0071) removed that constraint.
      final prepared = local is LocalCutoutAccepted
          ? _PreparedCutout(
              media: media,
              local: local,
              localCutoutPath: local.result.cutoutFilePath,
            )
          : await _cloudCutout(media);
      if (!mounted) {
        await _discardLocal();
        return;
      }
      // Start the mask upload NOW, not at Save: the naming step is dead time on
      // the network and exactly long enough to spend it.
      final acceptedLocal = prepared.local;
      _stagedMask = acceptedLocal == null ? null : _stageMask(acceptedLocal);
      setState(() {
        _prepared = prepared;
        _localSaving = false;
        _stage = _Stage.confirm;
      });
    } on _ReselectRequired {
      _fail(l10n.wtmAddReselectPhoto);
    } on _RemovalFailed catch (e) {
      // The removal itself failed. This — and only this — is what the retry
      // screen is for: retrying re-runs the removal, which is the thing that
      // went wrong.
      await _discardLocal();
      _fail(e.message);
    } on ApiException catch (e) {
      _fail(e.message);
    } on StateError catch (e) {
      _fail(e.message); // not signed in (upload guard)
    } catch (_) {
      _fail(l10n.addItemError);
    }
  }

  /// Remove the background in the cloud for an original that has no garment yet
  /// (local BG §0071) — the fallback when the device engine could not.
  ///
  /// Degrades rather than fails when the server cannot offer a temp cutout at
  /// all: a 404 means the build is talking to a backend without the endpoint, a
  /// 503 means private storage is off. Neither is a failed removal, and neither
  /// should block the add — the piece is saved and the worker cuts it afterwards,
  /// exactly as it did before this endpoint existed. The preview then says so
  /// instead of showing the original as though it were the result.
  Future<_PreparedCutout> _cloudCutout(MediaRef media) async {
    final l10n = AppLocalizations.of(context);
    final objectKey = media.objectKey;
    // Legacy bucket: no R2 key to hand the remover, so the worker cuts it after
    // the piece is saved, exactly as it did before this endpoint existed.
    if (objectKey == null) return _PreparedCutout(media: media);
    final AiJob job;
    try {
      job = await ref
          .read(wardrobeRepositoryProvider)
          .startCutoutJob(objectKey);
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 503) {
        return _PreparedCutout(media: media);
      }
      rethrow;
    }
    final terminal = await pollWtmAiJob(ref, job);
    if (!mounted) return _PreparedCutout(media: media);
    final url = terminal.outputUrl;
    if (terminal.status.isFailed || url == null) {
      throw _RemovalFailed(terminal.error ?? l10n.wtmAddRemovalFailed);
    }
    return _PreparedCutout(
      media: media,
      cutoutJobId: terminal.jobId,
      cutoutUrl: url,
    );
  }

  /// Create the garment from the already-finished cutout — the ONLY place the
  /// closet is written, and only ever from [_save].
  ///
  /// Through the local-cutout endpoint when the device produced the mask,
  /// otherwise through the plain create, which adopts the cloud `cutout_temp`
  /// job's output instead of queueing the worker to redo it.
  ///
  /// A local validation failure falls back to the cloud create **with the same
  /// original object key**, so the photo is never uploaded twice. The repository
  /// already retried transient failures idempotently, so anything that reaches the
  /// catch here is a decision, not a blip.
  /// Upload the mask to the user's private wardrobe sector and return its key.
  ///
  /// Never throws: every failure returns null so Save falls back to the inline
  /// bytes. `legacy` is deliberately a throw — there is no Supabase staging path,
  /// and with the R2 gate off the right answer is "no staged key", not a mask
  /// parked somewhere the create cannot read.
  Future<String?> _stageMask(LocalCutoutAccepted local) async {
    try {
      final bytes = await File(local.result.maskFilePath).readAsBytes();
      final stored = await ref
          .read(mediaUploadServiceProvider)
          .upload(
            bytes: bytes,
            sector: 'wardrobe',
            contentType: 'image/png',
            legacy: () => throw StateError('no legacy staging path'),
          );
      return stored.objectKey;
    } catch (_) {
      return null;
    }
  }

  Future<WardrobeItem> _createItem(
    _PreparedCutout prepared, {
    required String title,
    required String category,
  }) async {
    final media = prepared.media;
    final local = prepared.local;
    final objectKey = media.objectKey;
    final platform = Platform.isIOS ? 'ios' : 'android';
    final analytics = ref.read(analyticsProvider);
    if (local != null && objectKey != null) {
      try {
        // Awaiting a stage already in flight beats starting a fresh upload, and
        // a null just means we send the bytes as before.
        final stagedKey = await (_stagedMask ?? Future<String?>.value());
        final maskBytes = stagedKey != null
            ? null
            : await File(local.result.maskFilePath).readAsBytes();
        final item = await ref
            .read(wardrobeRepositoryProvider)
            .addItemWithLocalCutout(
              originalObjectKey: objectKey,
              maskPng: maskBytes,
              maskObjectKey: stagedKey,
              engine: local.result.engine.wireName,
              platform: platform,
              engineVersion: local.result.engineVersion,
              localLatencyMs: local.result.latency.inMilliseconds,
              subjectCount: local.result.metrics.subjectCount,
              title: title,
              category: category,
            );
        analytics.track(
          LocalCutoutEvents.persisted,
          properties: localCutoutPersistProperties(
            platform: platform,
            engine: local.result.engine,
            success: true,
          ),
        );
        return item;
      } on ApiException catch (error) {
        final reason = localCutoutReasonForApiError(error);
        analytics.track(
          LocalCutoutEvents.persisted,
          properties: localCutoutPersistProperties(
            platform: platform,
            engine: local.result.engine,
            success: false,
            failureCategory: localCutoutFailureCategory(error),
          ),
        );
        if (!reason.canUseCloudFallback) {
          // SOURCE_MISSING: the worker reads the same stored object, so a cloud
          // attempt is guaranteed to fail. Stop here and ask for a new photo
          // rather than creating a doomed item (§6.3).
          await _discardLocal();
          throw const _ReselectRequired();
        }
        // A rejected mask or a transient storage read: the original is already in
        // R2, so hand the SAME key to the cloud create and let BiRefNet make its
        // own mask. The photo is preserved either way.
        if (mounted) setState(() => _localSaving = false);
      } on Object {
        // An unreadable local file — treat as a plain fallback.
        if (mounted) setState(() => _localSaving = false);
      } finally {
        await _discardLocal();
      }
    }
    return ref
        .read(wardrobeRepositoryProvider)
        .addItem(
          title: title,
          category: category,
          imageUrl: media.legacyUrl,
          objectKey: objectKey,
          // Adopt the cutout the user has been looking at. Null only in the
          // degraded case where no temp cutout could be made, and then the server
          // queues the worker exactly as it always did.
          cutoutJobId: prepared.cutoutJobId,
        );
  }

  /// The build identity every local-BG event carries (§6).
  ///
  /// Without it a dashboard cannot answer the only question that matters after a
  /// release — "did THIS version break it" — because a fallback rate averaged over
  /// versions hides a total regression in the newest build behind healthy old ones.
  Map<String, Object> get _buildIdentity {
    final version = AppEnv.buildVersion;
    final plus = version.indexOf('+');
    return localCutoutBuildProperties(
      platform: Platform.isIOS ? 'ios' : 'android',
      appVersion: plus > 0
          ? version.substring(0, plus)
          : (version.isEmpty ? 'local' : version),
      buildNumber: plus > 0 ? version.substring(plus + 1) : 'local',
      shortGitSha: AppEnv.buildCommit.isEmpty ? 'local' : AppEnv.buildCommit,
    );
  }

  /// ONE event per Add Garment operation, whichever path it took (§6).
  ///
  /// This is the event the alerts read. A release where `local_attempted` collapses
  /// to near zero on a supported platform is an outage — even though every add still
  /// succeeds through the cloud, every build is green and the API stays healthy.
  /// That exact combination is what hid the last one for a whole version, so the
  /// signal is recorded on the success path too, not only on failures.
  void _trackOperation(
    LocalCutoutAttempt local, {
    required bool cloudFallbackUsed,
  }) {
    final orchestrator = _localCutout;
    final accepted = local is LocalCutoutAccepted;
    final reason = local is LocalCutoutRejected ? local.reason : null;
    final health = reason == null
        ? LocalCutoutHealth(
            state: LocalCutoutHealthState.enabledAndReady,
            engine: accepted ? local.result.engine : null,
            selfTest: orchestrator.lastSelfTest,
          )
        : LocalCutoutHealth(
            state: LocalCutoutHealth.stateForReason(reason),
            selfTest: orchestrator.lastSelfTest,
          );
    ref
        .read(analyticsProvider)
        .track(
          LocalCutoutEvents.operation,
          properties: localCutoutOperationProperties(
            build: _buildIdentity,
            health: health,
            localGateEnabled: orchestrator.isEnabledForThisBuild,
            // "Attempted" means the engine was actually asked. A gate that is off
            // or a device that cannot run it never reaches the engine, and counting
            // those as attempts would make a real outage invisible in the average.
            localAttempted:
                orchestrator.isEnabledForThisBuild &&
                reason != LocalCutoutFallbackReason.gateDisabled &&
                reason != LocalCutoutFallbackReason.unsupportedOs,
            localAccepted: accepted,
            cloudFallbackUsed: cloudFallbackUsed,
            engine: accepted ? local.result.engine : null,
            engineVersion: accepted ? local.result.engineVersion : 'unknown',
            fallbackReason: reason,
            nativeLatency: accepted ? local.result.latency : null,
          ),
        );
  }

  /// Record the local attempt's outcome with bucketed properties only (§10).
  ///
  /// Deliberately fired from ONE place, right after the attempt resolves, so a
  /// rebuild or a retry cannot double-count. The `gateDisabled` case is skipped
  /// entirely — a build with the feature off should produce no events at all.
  void _trackLocalOutcome(LocalCutoutAttempt local) {
    final platform = Platform.isIOS ? 'ios' : 'android';
    final analytics = ref.read(analyticsProvider);
    switch (local) {
      case LocalCutoutAccepted(:final result, :final warnings):
        analytics.track(
          LocalCutoutEvents.succeeded,
          properties: localCutoutSuccessProperties(
            platform: platform,
            engine: result.engine,
            metrics: result.metrics,
            latency: result.latency,
            warnings: warnings,
          ),
        );
        if (warnings.isNotEmpty) {
          analytics.track(
            LocalCutoutEvents.softWarning,
            properties: {
              ...localCutoutBaseProperties(
                platform: platform,
                engine: result.engine,
              ),
              'warnings': warnings.map((w) => w.name).toList()..sort(),
            },
          );
        }
      case LocalCutoutRejected(:final reason):
        if (reason == LocalCutoutFallbackReason.gateDisabled) return;
        final properties = localCutoutFallbackProperties(
          platform: platform,
          reason: reason,
        );
        analytics.track(
          reason == LocalCutoutFallbackReason.qualityRejected
              ? LocalCutoutEvents.hardRejected
              : LocalCutoutEvents.fallbackStarted,
          properties: properties,
        );
        if (!reason.canUseCloudFallback) {
          analytics.track(
            LocalCutoutEvents.sourceMissing,
            properties: properties,
          );
        }
    }
  }

  /// Delete the on-device scratch files. Idempotent, id-based (never a path), and
  /// safe to call after disposal.
  Future<void> _discardLocal() async {
    final operationId = _localOperationId;
    _localOperationId = null;
    if (operationId == null) return;
    await _localCutout.discard(operationId);
  }

  /// Show the exact local failure and offer to export its evidence.
  ///
  /// INTERNAL DIAGNOSTIC BUILDS ONLY, reachable only when
  /// `LocalCutoutRejected.hasExportableDiagnostics` is true, which requires the
  /// compile-time diagnostics gate. Returns true to continue with the cloud path.
  ///
  /// The copy here is deliberately NOT routed through `l10n`: it is developer-facing
  /// text in a build that never reaches a user or a translator, and adding these
  /// strings to the localisation surface would leave internal debug wording in the
  /// app's permanent translation set. Every user-visible string elsewhere still goes
  /// through `l10n` (§4.3).
  Future<bool> _surfaceLocalDiagnosticFailure(
    LocalCutoutRejected rejected,
    LocalCutoutOrchestrator orchestrator,
  ) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Local cutout failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reason: ${rejected.reason.name}'),
            const SizedBox(height: WtmSpace.s6),
            const Text(
              'Diagnostics were captured. Export the bundle, then choose whether '
              'to continue with the cloud cutout.',
            ),
          ],
        ),
        actions: [
          TextButton(
            // Deliberately does NOT dismiss: exporting and then deciding is the
            // normal flow, and re-running the whole add just to export would waste
            // a device session.
            onPressed: () async {
              final outcome = await orchestrator.exportDiagnostics(
                rejected.diagnosticOperationId,
              );
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('Diagnostics: ${outcome.name}')),
              );
            },
            child: const Text('Export bundle'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stop'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue with cloud'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _error = message;
    });
  }

  /// A missing name/category is a form problem, not a processing failure.
  ///
  /// So it does NOT get the full-screen error with its "Try again", which would
  /// re-run a background removal that already worked and fail identically. The
  /// user goes back to the field that is missing, with the photo, the cutout and
  /// everything they had already typed still intact — and, once the piece exists,
  /// to the confirm stage rather than back to a step it has moved past.
  void _failMetadata() {
    if (!mounted) return;
    setState(() {
      _showMetadataErrors = true;
      _error = null;
      _saving = false;
    });
  }

  /// Create the garment. The FIRST and only write to the closet in this flow.
  ///
  /// Everything before this produced an image and nothing else, so a user who
  /// backs out at any earlier point leaves no trace — and the piece that lands
  /// here is complete by construction: it carries the name and the category the
  /// user just supplied, and the cutout they have been looking at.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final prepared = _prepared;
    if (prepared == null) return;
    // The API refuses a piece with no name or no category, and it must keep
    // refusing. Checking here spends no round trip to be told so, and puts the
    // message on the field that is missing instead of in a failure sheet.
    if (!_metadataComplete) {
      _failMetadata();
      return;
    }
    if (_saving) return; // a second tap must not create a second garment
    setState(() => _saving = true);
    final title = _name.text.trim();
    final category = _category!.name;
    try {
      final created = await _createItem(
        prepared,
        title: title,
        category: category,
      );
      if (!mounted) return;
      // The premium enhance runs on the piece that now exists. If it cannot
      // start (out of credits, studio down) the garment still lands as a plain
      // cutout — never lost because the extra step failed.
      if (_enhance) {
        try {
          final job = await ref
              .read(aiStudioRepositoryProvider)
              .enhanceItem(created.id);
          ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
          ref.invalidate(creditsProvider);
          if (!mounted) return;
          setState(() => _enhancePhase = true);
          final terminal = await pollWtmAiJob(ref, job);
          if (!mounted) return;
          if (terminal.status.isFailed) {
            _enhanceError = terminal.error ?? l10n.wardrobeEnhanceError;
          }
          ref.invalidate(
            creditsProvider,
          ); // charged on success, refunded on fail
        } on ApiException catch (e) {
          if (mounted) setState(() => _enhanceError = e.message);
        }
      }
      // Enhance rewrites the stored image, so that path still needs the server's
      // version. A plain save does not: `created` IS the stored row, so putting
      // it straight into the grid saves a full closet fetch the user was
      // otherwise made to wait through before the screen would even close.
      if (_enhance) {
        await ref.read(wardrobeItemsProvider.notifier).refresh();
      } else {
        ref.read(wardrobeItemsProvider.notifier).insertItem(created);
      }
      if (!mounted) return;
      wtmSnack(context, _enhanceError ?? l10n.wtmAddSavedToast);
      wtmPageBack(context);
    } on _ReselectRequired {
      // The stored original is gone, so no create can succeed from this photo.
      _fail(l10n.wtmAddReselectPhoto);
    } on ApiException catch (e) {
      if (!mounted) return;
      // A rejected create is NOT a failed background removal. The cutout is
      // still good and still on screen; the user stays here, keeps everything
      // they typed, and is told what to fix — never sent to a retry that would
      // re-run a removal that worked.
      wtmSnack(context, e.message);
      setState(() {
        _saving = false;
        if (e.code == ApiErrorCode.validationError) _showMetadataErrors = true;
      });
    } catch (_) {
      if (!mounted) return;
      wtmSnack(context, l10n.addItemError);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmPage(
      title: l10n.wtmAddTitle,
      eyebrow: switch (_stage) {
        _Stage.capture => l10n.wtmAddCaptureEyebrow,
        _Stage.processing => l10n.wtmAddProcessingEyebrow,
        _Stage.confirm => l10n.wtmAddConfirmEyebrow,
        _Stage.failed => l10n.errorGenericTitle,
      },
      children: switch (_stage) {
        _Stage.capture => _capture(l10n),
        _Stage.processing => _processing(l10n),
        _Stage.confirm => _confirm(l10n),
        _Stage.failed => [
          const SizedBox(height: WtmSpace.s22),
          WtmErrorState(
            title: l10n.errorGenericTitle,
            message: _error ?? l10n.addItemError,
            retryLabel: l10n.commonRetry,
            // This state is only ever reached by a failed REMOVAL, so retrying
            // re-runs the removal — the thing that actually went wrong. A
            // rejected save never lands here; it stays on the form.
            onRetry: _bytes == null
                ? () => setState(() => _stage = _Stage.capture)
                : _run,
          ),
        ],
      },
    );
  }

  List<Widget> _capture(AppLocalizations l10n) {
    final credits = ref.watch(creditsProvider).asData?.value;
    final isSubscriber = credits?.isSubscriber ?? false;
    return [
      Text(
        l10n.wtmAddCaptureTitle,
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        l10n.wtmAddCaptureMessage,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      const SizedBox(height: WtmSpace.s16),
      AuroraBox(
        height: 200,
        vignette: true,
        child: const Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: WtmIcon(WtmGlyph.hanger, size: 40, color: WtmColors.gold),
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
      // "Choose how to add this piece" — the shipped composer's free bg-removal
      // vs premium AI Enhance choice, in Atelier dress.
      EyebrowLabel(l10n.addPieceHowTitle),
      const SizedBox(height: WtmSpace.s10),
      _ModeCard(
        selected: !_enhance,
        glyph: WtmGlyph.erase,
        title: l10n.addPieceRemoveBgTitle,
        subtitle: l10n.addPieceRemoveBgSub,
        onTap: () => setState(() => _enhance = false),
      ),
      const SizedBox(height: WtmSpace.s8),
      _ModeCard(
        selected: _enhance,
        glyph: WtmGlyph.sparkle,
        title: l10n.addPieceEnhanceTitle,
        subtitle: l10n.addPieceEnhanceSub,
        description: l10n.addPieceEnhanceDesc,
        locked: !isSubscriber,
        onTap: () {
          // Free users see AI Enhance but it's locked → paywall (§18).
          if (!isSubscriber) {
            context.push(AppRoute.wtmPaywall);
            return;
          }
          setState(() => _enhance = true);
        },
      ),
      const SizedBox(height: WtmSpace.s8),
      Text(l10n.aiUploadDisclaimer, style: WtmType.micro),
      const SizedBox(height: WtmSpace.s14),
      GradientCta(
        label: l10n.wtmAddTakePhoto,
        icon: const WtmIcon(
          WtmGlyph.camera,
          size: 15,
          color: WtmColors.ctaText,
        ),
        onPressed: () => _pick(ImageSource.camera),
      ),
      const SizedBox(height: WtmSpace.s10),
      GhostButton(
        label: l10n.wtmAddFromGallery,
        icon: const WtmIcon(WtmGlyph.image, size: 15, color: WtmColors.text),
        onPressed: () => _pick(ImageSource.gallery),
      ),
    ];
  }

  /// The name field, shared by the details and confirm stages so the piece is
  /// described the same way whether it is being created or being confirmed.
  Widget _nameField(AppLocalizations l10n) {
    final missing = _showMetadataErrors && _name.text.trim().isEmpty;
    return TextField(
      controller: _name,
      style: WtmType.body,
      cursorColor: WtmColors.gold,
      // Continue/Save enable on the first character, and the red clears as they
      // type rather than staying up until the next rejected tap.
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: l10n.wtmGarmentNameHint,
        hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
        errorText: missing ? l10n.addItemNameRequiredError : null,
        errorStyle: WtmType.micro.copyWith(color: WtmColors.danger),
        filled: true,
        fillColor: WtmColors.iconBtnBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: BorderSide(
            color: missing ? WtmColors.danger : WtmColors.line,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: BorderSide(
            color: missing ? WtmColors.danger : WtmColors.chipOnBorder,
          ),
        ),
      ),
    );
  }

  /// The category chips, shared by the details and confirm stages.
  List<Widget> _categoryChips(AppLocalizations l10n) => [
    Wrap(
      spacing: WtmSpace.s6,
      runSpacing: WtmSpace.s6,
      children: [
        for (final c in ClosetCategory.values)
          if (c != ClosetCategory.all && c != ClosetCategory.favorites)
            WtmChip(
              label: c.label(l10n),
              on: _category == c,
              onTap: () =>
                  setState(() => _category = _category == c ? null : c),
            ),
      ],
    ),
    if (_showMetadataErrors && _category == null) ...[
      const SizedBox(height: WtmSpace.s6),
      Text(
        l10n.addItemCategoryRequiredError,
        style: WtmType.micro.copyWith(color: WtmColors.danger),
      ),
    ],
  ];

  List<Widget> _processing(AppLocalizations l10n) {
    return [
      // The picked shot under the aurora treatment while the atelier works
      // (post-hoc enhance re-enters here with no fresh bytes — show the piece).
      AspectSafeMedia(
        // Whichever of the two is actually on screen decides the shape.
        image: _localCutoutPath != null
            ? FileImage(File(_localCutoutPath!))
            : MemoryImage(_bytes ?? Uint8List(0)) as ImageProvider,
        minHeight: _previewMinHeight,
        maxHeight: _previewMaxHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WtmRadius.tile),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The instant on-device cutout, the moment the engine writes it.
              // `contain` (not `cover`) because a cutout must not be cropped —
              // and the fallbacks below used to be `cover`, which quietly
              // undid that the moment the cache file went missing.
              if (_localCutoutPath != null)
                Image.file(
                  File(_localCutoutPath!),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  // A missing/short-lived cache file must never break the screen.
                  errorBuilder: (_, _, _) => _bytes != null
                      ? Image.memory(_bytes!, fit: BoxFit.contain)
                      : const SizedBox.shrink(),
                )
              else if (_bytes != null)
                Image.memory(
                  _bytes!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              // No third branch: this stage is only ever reached with a picked
              // photo in hand. It used to be re-entered by the post-hoc enhance,
              // which needed a saved garment to render — and that affordance is
              // gone, because at this point in the flow no garment exists.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: WtmGradients.vignetteRadial,
                ),
              ),
              const GrainOverlay(),
            ],
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
      Text(
        // Three distinct waits, three truthful labels:
        //  * enhance keeps its own copy;
        //  * the LOCAL path is seconds long, so it says exactly what it is doing
        //    and never borrows the staged 90s cold-start copy;
        //  * the cloud path keeps the staged warming → clearing → refining text,
        //    which is honest for a scale-to-zero worker.
        _enhancePhase
            ? l10n.wardrobeEnhanceStarted
            : _localSaving
            ? l10n.wtmAddLocalSaving
            : _isLocalAttempt
            ? l10n.wtmAddLocalRemoving
            : _stageText(l10n),
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        // Honest expectation-setting during the cutout wait (first item warms up,
        // next ones are faster). The local preview says the save is still running.
        _enhancePhase
            ? l10n.wtmAddProcessingHint
            : _localSaving
            ? l10n.wtmAddLocalPreviewNote
            : _isLocalAttempt
            ? l10n.wtmAddProcessingHint
            : l10n.wardrobeWaitNote,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      // The rotating tip exists to fill a ~90s cloud wait; on the local path there
      // is nothing to fill.
      if (!_enhancePhase && !_isLocalAttempt) ...[
        const SizedBox(height: WtmSpace.s10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            _tip(l10n),
            key: ValueKey(_tip(l10n)),
            textAlign: TextAlign.center,
            style: WtmType.sub.copyWith(color: WtmColors.gold),
          ),
        ),
      ],
      const SizedBox(height: WtmSpace.s16),
      const WtmGoldProgress(),
    ];
  }

  /// The finished cutout, then the two mandatory fields, then Save.
  ///
  /// The user has already seen what the removal produced — that is the whole
  /// point of this stage coming after processing rather than before it. Nothing
  /// is in the closet yet; Save is what creates the piece.
  List<Widget> _confirm(AppLocalizations l10n) {
    final prepared = _prepared!;
    return [
      Text(
        l10n.wtmAddConfirmTitle,
        textAlign: TextAlign.center,
        style: WtmType.h2.copyWith(fontSize: 19),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(
        // Honest about which of the two things they are looking at: the finished
        // cutout, or the original with the removal still to come.
        prepared.hasCutout
            ? l10n.wtmAddConfirmMessage
            : l10n.wtmAddCutoutAfterSave,
        textAlign: TextAlign.center,
        style: WtmType.sub,
      ),
      const SizedBox(height: WtmSpace.s16),
      // The finished cutout at ITS shape, not squeezed into the closet grid's
      // 3:4 tile. A pair of trousers and a wide coat are different rectangles,
      // and this is the screen where someone decides whether the removal did
      // the right thing — so it has to show what the file actually is.
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _confirmPreviewMaxWidth),
          child: AspectSafeMedia(
            image: _previewImageFor(prepared),
            minHeight: _confirmPreviewMinHeight,
            maxHeight: _confirmPreviewMaxHeight,
            child: _cutoutPreview(l10n, prepared),
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s14),
      _nameField(l10n),
      const SizedBox(height: WtmSpace.s12),
      ..._categoryChips(l10n),
      // The enhance job failed (e.g. the AI studio is unavailable) — say so
      // honestly with the server's reason; the plain cutout is still saved and
      // the credit was refunded (mobile QA #5: never end silently).
      if (_enhanceError != null) ...[
        const SizedBox(height: WtmSpace.s12),
        Container(
          padding: const EdgeInsets.all(WtmSpace.s12),
          decoration: BoxDecoration(
            color: WtmColors.iconBtnBg,
            borderRadius: BorderRadius.circular(WtmRadius.tile),
            border: Border.all(color: WtmColors.danger),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WtmIcon(WtmGlyph.shield, size: 15, color: WtmColors.danger),
              const SizedBox(width: WtmSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.wtmEnhanceFailedTitle,
                      style: WtmType.labelMedium.copyWith(
                        color: WtmColors.danger,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _enhanceError!,
                      style: WtmType.micro.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: WtmSpace.s16),
      GradientCta(
        label: l10n.wtmAddSaveCta,
        icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.ctaText),
        onPressed: _saving ? null : _save,
      ),
      const SizedBox(height: WtmSpace.s10),
      GhostButton(
        label: l10n.wtmAddChangePhoto,
        icon: const WtmIcon(WtmGlyph.image, size: 15, color: WtmColors.text),
        // Back to the picker WITHOUT dropping what they typed — a different
        // photo of the same garment keeps its name and category.
        onPressed: _saving
            ? null
            : () {
                unawaited(_discardLocal());
                setState(() {
                  _prepared = null;
                  _bytes = null;
                  _localCutoutPath = null;
                  _showMetadataErrors = false;
                  _stage = _Stage.capture;
                });
              },
      ),
      // "Enhance item" and "Fix cutout" are deliberately NOT here any more: both
      // act on a garment, and at this point in the flow no garment exists yet —
      // that is what makes the removal-first order possible. Both remain on the
      // garment detail screen, one tap away once the piece is saved.
    ];
  }

  /// What the removal produced: the on-device file, the cloud cutout, or — when
  /// neither engine could deliver one — the original, labelled as such by the
  /// copy above rather than passed off as a finished cutout.
  /// The provider whose intrinsic size shapes the confirm preview — the SAME
  /// source [_cutoutPreview] is about to paint, so the box and the picture can
  /// never disagree.
  ImageProvider _previewImageFor(_PreparedCutout prepared) {
    final localPath = prepared.localCutoutPath;
    if (localPath != null) return FileImage(File(localPath));
    final url = prepared.cutoutUrl;
    if (url != null) {
      return CachedNetworkImageProvider(
        url,
        cacheKey: renditionImageCacheKey(url, isCutout: true),
      );
    }
    return MemoryImage(_bytes ?? Uint8List(0));
  }

  Widget _cutoutPreview(AppLocalizations l10n, _PreparedCutout prepared) {
    final localPath = prepared.localCutoutPath;
    if (localPath != null) {
      return Image.file(
        File(localPath),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        semanticLabel: l10n.wtmAddConfirmTitle,
        // A short-lived cache file must never break the stage the user is
        // standing on; fall back to the photo they picked.
        errorBuilder: (_, _, _) => _originalPreview(l10n),
      );
    }
    final url = prepared.cutoutUrl;
    if (url != null) {
      return FabricTile(
        imageUrl: url,
        isCutout: true,
        swatchIndex: url.hashCode.abs() % 8,
        fit: BoxFit.contain,
        // The enclosing AspectSafeMedia already carries the cutout's own shape;
        // the tile's default 3:4 would impose the closet grid's rectangle on
        // top of it and put the letterbox straight back.
        aspectRatio: null,
        semanticLabel: l10n.wtmAddConfirmTitle,
      );
    }
    return _originalPreview(l10n);
  }

  Widget _originalPreview(AppLocalizations l10n) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: l10n.wtmAddConfirmTitle,
    );
  }
}

/// "Choose how to add this piece" option card — free Remove background vs the
/// premium AI Enhance (locked for free users), Atelier-dressed version of the
/// shipped composer's choice.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.description,
    this.locked = false,
  });

  final bool selected;
  final WtmGlyph glyph;
  final String title;
  final String subtitle;
  final String? description;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(WtmSpace.s12),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(
                color: selected ? WtmColors.chipOnBorder : WtmColors.line,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WtmColors.riconBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WtmColors.riconBorder),
                  ),
                  alignment: Alignment.center,
                  child: WtmIcon(
                    glyph,
                    size: 15,
                    color: selected ? WtmColors.gold : WtmColors.muted,
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: WtmType.labelMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: WtmType.micro),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(description!, style: WtmType.micro),
                      ],
                    ],
                  ),
                ),
                if (locked)
                  const Padding(
                    padding: EdgeInsets.only(left: WtmSpace.s8),
                    child: WtmIcon(
                      WtmGlyph.shield,
                      size: 14,
                      color: WtmColors.faint,
                    ),
                  )
                else if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: WtmSpace.s8),
                    child: WtmIcon(
                      WtmGlyph.check,
                      size: 14,
                      color: WtmColors.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Indeterminate thin gold progress line (board `.track`/`.fill`) — a sweeping
/// gold segment; static half-fill under reduced motion.
class WtmGoldProgress extends StatefulWidget {
  const WtmGoldProgress({super.key});

  @override
  State<WtmGoldProgress> createState() => _WtmGoldProgressState();
}

class _WtmGoldProgressState extends State<WtmGoldProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0x1CFFFFFF), // .track
                      borderRadius: BorderRadius.circular(WtmRadius.chip),
                    ),
                  ),
                  if (reduceMotion)
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: WtmGradients.sliderFill,
                          borderRadius: BorderRadius.circular(WtmRadius.chip),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      left: (width + 120) * t - 120,
                      width: 120,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: WtmGradients.sliderFill,
                          borderRadius: BorderRadius.circular(WtmRadius.chip),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

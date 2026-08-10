import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wtm_giveaway_delete.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/giveaway.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Secret Pickup Chat (giveaways) — the private, 7-day owner ↔ accepted-
/// requester coordination room. Text-only (≤500 chars), quick-reply chips, a
/// pickup-plan card, and a persistent safety strip. Locks itself the moment
/// the window ends, the item is given, or the request is cancelled; message
/// bodies are redacted server-side afterwards (§10).
class WtmGiveawayChatScreen extends ConsumerStatefulWidget {
  const WtmGiveawayChatScreen({super.key, required this.giveawayId});

  final String giveawayId;

  @override
  ConsumerState<WtmGiveawayChatScreen> createState() =>
      _WtmGiveawayChatScreenState();
}

/// A locally-composed message that hasn't been confirmed by the server yet.
class _PendingMessage {
  _PendingMessage(this.body) : at = DateTime.now();
  final String body;
  final DateTime at;
  bool failed = false;
}

/// Soft heads-up when a draft looks like a phone number or an email — the app
/// never blocks on this (moderation server-side does the hard checks).
bool looksLikeContactInfo(String text) {
  final phone = RegExp(r'\+?\d[\d\s\-().]{7,}\d');
  final email = RegExp(r'[\w.+-]+@[\w-]+\.\w{2,}');
  return phone.hasMatch(text) || email.hasMatch(text);
}

class _WtmGiveawayChatScreenState extends ConsumerState<WtmGiveawayChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  GiveawayPickupChat? _chat;
  List<GiveawayChatMessage> _messages = const [];
  final List<_PendingMessage> _outbox = [];
  bool _loading = true;
  bool _failed = false;
  bool _contactWarning = false;

  /// True when messages arrived while the user was reading older ones. Drives
  /// the jump-to-latest affordance instead of force-scrolling them away.
  bool _unseenBelow = false;
  Timer? _poll;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.giveawayChatOpened);
    _composer.addListener(_onDraftChanged);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    final warn = looksLikeContactInfo(_composer.text);
    if (warn != _contactWarning) setState(() => _contactWarning = warn);
  }

  /// In a reversed list offset 0 IS the newest message, so "near zero" is "at
  /// the bottom". A small tolerance keeps a one-pixel overscroll from counting
  /// as scrolled-away.
  static const _atBottomSlack = 24.0;

  bool get _isAtBottom =>
      !_scroll.hasClients || _scroll.offset <= _atBottomSlack;

  void _onScroll() {
    // Reaching the bottom clears the indicator — the user has seen them.
    if (_unseenBelow && _isAtBottom) {
      setState(() => _unseenBelow = false);
    }
  }

  Future<void> _load() async {
    final repo = ref.read(giveawayRepositoryProvider);
    try {
      final chat = await repo.getChat(widget.giveawayId);
      final messages = chat == null
          ? const <GiveawayChatMessage>[]
          : await repo.chatMessages(chat.id);
      if (!mounted) return;
      setState(() {
        _chat = chat;
        _messages = messages;
        _loading = false;
        _failed = false;
      });
      _armPolling();
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Light polling while the chat is live: messages every 5s, the chat row
  /// itself every 30s (it can lock from the other side at any moment).
  void _armPolling() {
    _poll?.cancel();
    final chat = _chat;
    if (chat == null || !chat.isActive) return;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  Future<void> _tick() async {
    final chat = _chat;
    if (chat == null) return;
    _ticks++;
    final repo = ref.read(giveawayRepositoryProvider);
    try {
      final messages = await repo.chatMessages(chat.id);
      GiveawayPickupChat? fresh = chat;
      if (_ticks % 6 == 0) fresh = await repo.getChat(widget.giveawayId);
      if (!mounted) return;

      // Nothing changed on this tick — and most ticks change nothing. Rebuilding
      // the whole conversation anyway is what made typing feel unsteady every
      // five seconds.
      final changed =
          messages.length != _messages.length ||
          (messages.isNotEmpty &&
              _messages.isNotEmpty &&
              messages.last.id != _messages.last.id) ||
          fresh?.status != _chat?.status;
      if (!changed) return;

      // Decide BEFORE the rebuild: if they are reading older messages, the new
      // one must not drag them to the bottom.
      final arrived = messages.length > _messages.length;
      final away = !_isAtBottom;
      setState(() {
        _messages = messages;
        _chat = fresh;
        if (arrived && away) _unseenBelow = true;
      });
      if (fresh == null || !fresh.isActive) _poll?.cancel();
    } on ApiException catch (e) {
      // A 404 mid-conversation is not a blip: the owner deleted the giveaway,
      // which takes the chat with it for BOTH sides by design. Leave rather
      // than poll a conversation that no longer exists.
      if (e.statusCode == 404) {
        await _handleGiveawayGone();
        return;
      }
      // transient poll miss — keep the last known state, try again next tick
    }
  }

  /// The giveaway (and with it this chat) was deleted by its owner.
  ///
  /// Deletion is deliberately permanent and cascades to claims and chat, so the
  /// other participant has to be told plainly and moved somewhere real — not
  /// left on a loader, an error retry, or a transcript that no longer exists.
  /// Nothing about the conversation is kept locally.
  Future<void> _handleGiveawayGone() async {
    _poll?.cancel();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    refreshGiveawayLists(ref, id: widget.giveawayId);
    wtmSnack(context, l10n.giveawayDeletedByOwner);
    wtmPageBack(context);
  }

  // ── sending (optimistic, retryable) ────────────────────────────────────────

  Future<void> _send(String raw) async {
    final chat = _chat;
    final body = raw.trim();
    if (chat == null || !chat.isActive || body.isEmpty) return;
    final pending = _PendingMessage(body);
    setState(() {
      _outbox.add(pending);
      _composer.clear();
    });
    await _deliver(pending);
  }

  Future<void> _deliver(_PendingMessage pending) async {
    final chat = _chat;
    if (chat == null) return;
    try {
      final sent = await ref
          .read(giveawayRepositoryProvider)
          .sendChatMessage(chat.id, pending.body);
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.giveawayChatMessageSent);
      if (!mounted) return;
      setState(() {
        _outbox.remove(pending);
        _messages = [..._messages, sent];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // The conversation itself is gone — the owner deleted the giveaway. Do
      // not leave a failed bubble the user can retry into a void.
      if (e.statusCode == 404) {
        await _handleGiveawayGone();
        return;
      }
      setState(() => pending.failed = true);
      // A locked/expired chat rejects sends — refresh so the banner flips.
      if (e.code == ApiErrorCode.validationError) await _load();
      if (e.code == ApiErrorCode.moderationBlocked && mounted) {
        wtmSnack(context, e.message);
      }
    }
  }

  Future<void> _retry(_PendingMessage pending) async {
    setState(() => pending.failed = false);
    await _deliver(pending);
  }

  // ── owner / requester actions ──────────────────────────────────────────────

  Future<void> _markGiven() async {
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.wtmGiveawayMarkGivenTitle,
      message: l10n.wtmGiveawayMarkGivenBody,
      confirmLabel: l10n.wtmGiveawayMarkGiven,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(giveawayRepositoryProvider)
          .updateStatus(widget.giveawayId, 'claimed');
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.giveawayMarkedGiven);
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
      ref.invalidate(myGiveawaysProvider);
      if (mounted) wtmSnack(context, l10n.wtmGiveawayUpdated);
      await _load();
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  Future<void> _cancelRequest() async {
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.wtmGiveawayCancelRequestTitle,
      message: l10n.wtmGiveawayCancelRequestBody,
      confirmLabel: l10n.wtmGiveawayCancelRequest,
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(giveawayRepositoryProvider).cancelClaim(widget.giveawayId);
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.giveawayClaimCancelled);
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
      if (mounted) wtmSnack(context, l10n.wtmGiveawayRequestCancelled);
      await _load();
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  Future<void> _report() async {
    final chat = _chat;
    if (chat == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.wtmChatReportTitle,
      message: l10n.wtmChatReportBody,
      confirmLabel: l10n.wtmChatMenuReport,
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(giveawayRepositoryProvider).reportChat(chat.id);
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.giveawayChatReported);
      if (mounted) wtmSnack(context, l10n.wtmChatReported);
      await _load();
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  Future<void> _block() async {
    final chat = _chat;
    if (chat == null) return;
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.wtmChatBlockTitle,
      message: l10n.wtmChatBlockBody,
      confirmLabel: l10n.wtmChatMenuBlock,
      danger: true,
    );
    if (!ok || !mounted) return;
    final other = chat.isOwner ? chat.requesterId : chat.ownerId;
    try {
      await ref.read(socialRepositoryProvider).block(other);
      // Blocking ends the pickup from whichever side did it.
      if (chat.isOwner) {
        await ref
            .read(giveawayRepositoryProvider)
            .updateStatus(widget.giveawayId, 'closed');
      } else {
        await ref
            .read(giveawayRepositoryProvider)
            .cancelClaim(widget.giveawayId);
      }
      ref.invalidate(giveawayDetailProvider(widget.giveawayId));
      if (mounted) wtmSnack(context, l10n.wtmChatBlocked);
      await _load();
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  void _openMenu() {
    final chat = _chat;
    if (chat == null) return;
    final l10n = AppLocalizations.of(context);
    showWtmSheet(
      context,
      title: l10n.wtmChatTitle,
      subtitle: chat.giveawayTitle,
      children: [
        if (chat.isOwner && chat.isActive) ...[
          GhostButton(
            label: l10n.wtmGiveawayMarkGiven,
            icon: const WtmIcon(
              WtmGlyph.check,
              size: 15,
              color: WtmColors.gold,
            ),
            foregroundColor: WtmColors.gold,
            onPressed: () {
              Navigator.of(context).pop();
              _markGiven();
            },
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        if (!chat.isOwner && chat.isActive) ...[
          GhostButton(
            label: l10n.wtmGiveawayCancelRequest,
            icon: const WtmIcon(
              WtmGlyph.erase,
              size: 15,
              color: WtmColors.danger,
            ),
            foregroundColor: WtmColors.danger,
            onPressed: () {
              Navigator.of(context).pop();
              _cancelRequest();
            },
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        GhostButton(
          label: l10n.wtmChatMenuReport,
          icon: const WtmIcon(
            WtmGlyph.shield,
            size: 15,
            color: WtmColors.danger,
          ),
          foregroundColor: WtmColors.danger,
          onPressed: () {
            Navigator.of(context).pop();
            _report();
          },
        ),
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: l10n.wtmChatMenuBlock,
          icon: const WtmIcon(
            WtmGlyph.users,
            size: 15,
            color: WtmColors.danger,
          ),
          foregroundColor: WtmColors.danger,
          onPressed: () {
            Navigator.of(context).pop();
            _block();
          },
        ),
      ],
    );
  }

  // ── pickup plan ────────────────────────────────────────────────────────────

  Future<void> _editPlan({bool confirm = false}) async {
    final chat = _chat;
    if (chat == null || !chat.isActive) return;
    final l10n = AppLocalizations.of(context);
    if (confirm) {
      await _savePlan(
        area: chat.planArea,
        landmark: chat.planLandmark,
        timeSlot: chat.planTimeSlot,
        confirmed: true,
      );
      return;
    }
    final saved = await showModalBottomSheet<_PlanDraft>(
      context: context,
      backgroundColor: WtmColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(WtmRadius.sheetTop),
        ),
      ),
      builder: (context) => _PlanSheet(chat: chat, l10n: l10n),
    );
    if (saved != null) {
      await _savePlan(
        area: saved.area,
        landmark: saved.landmark,
        timeSlot: saved.timeSlot,
        confirmed: chat.planConfirmed,
      );
    }
  }

  Future<void> _savePlan({
    String? area,
    String? landmark,
    String? timeSlot,
    required bool confirmed,
  }) async {
    final chat = _chat;
    if (chat == null) return;
    final l10n = AppLocalizations.of(context);
    try {
      final fresh = await ref
          .read(giveawayRepositoryProvider)
          .updatePickupPlan(
            chat.id,
            area: area,
            landmark: landmark,
            timeSlot: timeSlot,
            confirmed: confirmed,
          );
      if (!mounted) return;
      setState(() => _chat = fresh);
      wtmSnack(context, l10n.wtmChatPlanSaved);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    }
  }

  // ── view ───────────────────────────────────────────────────────────────────

  String _timeLeftLabel(AppLocalizations l10n, GiveawayPickupChat chat) {
    final left = chat.timeLeft;
    if (left.inDays > 0) {
      return l10n.wtmChatDaysHours(left.inDays, left.inHours % 24);
    }
    if (left.inHours > 0) return l10n.wtmChatHoursOnly(left.inHours);
    return l10n.wtmChatLessThanHour;
  }

  String _lockedCopy(AppLocalizations l10n, GiveawayPickupChat chat) {
    switch (chat.status) {
      case 'completed':
        return l10n.wtmChatLockedCompleted;
      case 'cancelled':
        return l10n.wtmChatLockedCancelled;
      default:
        return l10n.wtmChatLockedExpired;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chat = _chat;

    return WtmScaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _NavHead(
              title: l10n.wtmChatTitle,
              eyebrow: chat?.otherName == null
                  ? l10n.wtmChatEyebrow
                  : '${l10n.wtmChatEyebrow} · ${chat!.otherName}',
              onMenu: chat == null ? null : _openMenu,
            ),
            if (_loading)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.all(WtmSpace.screenH),
                  child: Column(
                    children: [
                      LoadingShimmer(width: double.infinity, height: 44),
                      SizedBox(height: WtmSpace.s10),
                      Expanded(
                        child: LoadingShimmer(
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_failed)
              Expanded(
                child: Center(
                  child: WtmErrorState(
                    title: l10n.wtmChatErrorTitle,
                    message: l10n.errorGenericTitle,
                    retryLabel: l10n.commonRetry,
                    onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    },
                  ),
                ),
              )
            else if (chat == null)
              Expanded(
                child: Center(
                  child: WtmEmptyState(
                    glyph: WtmGlyph.gift,
                    title: l10n.wtmChatNoneTitle,
                    message: l10n.wtmChatNoneMessage,
                  ),
                ),
              )
            else
              Expanded(child: _chatBody(l10n, chat)),
          ],
        ),
      ),
    );
  }

  Widget _chatBody(AppLocalizations l10n, GiveawayPickupChat chat) {
    final active = chat.isActive;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            0,
            WtmSpace.screenH,
            WtmSpace.s8,
          ),
          child: Column(
            children: [
              if (active)
                _Banner(
                  glyph: WtmGlyph.bell,
                  color: WtmColors.gold,
                  background: WtmColors.pillBg,
                  border: WtmColors.pillBorder,
                  text: l10n.wtmChatExpiresIn(_timeLeftLabel(l10n, chat)),
                )
              else
                _Banner(
                  glyph: WtmGlyph.shield,
                  color: WtmColors.muted,
                  background: WtmColors.chipBg,
                  border: WtmColors.line,
                  text: _lockedCopy(l10n, chat),
                ),
              const SizedBox(height: WtmSpace.s8),
              _PlanCard(
                chat: chat,
                l10n: l10n,
                onEdit: active ? () => _editPlan() : null,
                onConfirm: active && chat.hasPlan && !chat.planConfirmed
                    ? () => _editPlan(confirm: true)
                    : null,
              ),
              // Conversation-level safety information, up here with the other
              // conversation-level information. It used to sit pinned directly
              // above the composer, where a permanent notice reads as something
              // attached to — or worse, typed into — the input.
              const SizedBox(height: WtmSpace.s8),
              _SafetyStrip(
                key: const Key('wtm-chat-safety'),
                text: l10n.wtmChatSafety,
              ),
            ],
          ),
        ),
        Expanded(child: _messageList(l10n, chat)),
        if (active) ...[
          const SizedBox(height: WtmSpace.s8),
          WtmChipRow(
            padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
            children: [
              for (final quick in [
                l10n.wtmChatQuickToday,
                l10n.wtmChatQuickTomorrow,
                l10n.wtmChatQuickPublic,
                l10n.wtmChatQuickOnMyWay,
                l10n.wtmChatQuickArrived,
                l10n.wtmChatQuickConfirmed,
              ])
                WtmChip(label: quick, onTap: () => _send(quick)),
            ],
          ),
        ],
        const SizedBox(height: WtmSpace.s8),
        _composerBar(l10n, active),
      ],
    );
  }

  Widget _messageList(AppLocalizations l10n, GiveawayPickupChat chat) {
    // Newest at the bottom; reversed so the list sticks to the latest message.
    final items = <Widget>[
      for (final m in _messages) _MessageBubble.server(m, l10n),
      for (final p in _outbox)
        _MessageBubble.pending(p, l10n, onRetry: () => _retry(p)),
    ].reversed.toList();

    if (items.isEmpty) {
      return Center(child: Text(l10n.wtmChatEmpty, style: WtmType.sub));
    }
    return Stack(
      children: [
        ListView(
          controller: _scroll,
          reverse: true,
          // The extra bottom inset (which is the reversed list's LEADING edge)
          // keeps the newest message clear of the composer stack instead of
          // sitting flush against it — the thing that made a system notice look
          // like part of the input.
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s8,
            WtmSpace.screenH,
            WtmSpace.s12,
          ),
          children: items,
        ),
        // Only while the user is reading older messages. Jumping them to the
        // bottom on every poll would yank them out of what they are reading;
        // saying nothing would hide the fact that something arrived.
        if (_unseenBelow)
          Positioned(
            bottom: WtmSpace.s8,
            left: 0,
            right: 0,
            child: Center(
              child: GoldPill(
                key: const Key('wtm-chat-new-messages'),
                label: l10n.wtmChatNewMessages,
                icon: const WtmIcon(
                  WtmGlyph.chevron,
                  size: 12,
                  color: WtmColors.gold,
                ),
                onTap: _jumpToLatest,
              ),
            ),
          ),
      ],
    );
  }

  /// Scroll the (reversed) list back to the newest message.
  void _jumpToLatest() {
    setState(() => _unseenBelow = false);
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: WtmMotion.base, curve: WtmMotion.easing);
  }

  Widget _composerBar(AppLocalizations l10n, bool active) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Draft validation, OUTSIDE the composer's own surface. It used to
        // render inside the bar above the text field, which made the input
        // itself look like a notification and put app-authored copy in the
        // place the user's own words belong.
        if (_contactWarning && active)
          Padding(
            key: const Key('wtm-chat-contact-warning'),
            padding: const EdgeInsets.fromLTRB(
              WtmSpace.screenH,
              0,
              WtmSpace.screenH,
              WtmSpace.s6,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: WtmIcon(
                    WtmGlyph.shield,
                    size: 12,
                    color: WtmColors.gold,
                  ),
                ),
                const SizedBox(width: WtmSpace.s6),
                Expanded(
                  child: Text(
                    l10n.wtmChatContactWarning,
                    style: WtmType.micro.copyWith(color: WtmColors.gold),
                  ),
                ),
              ],
            ),
          ),
        _composerSurface(l10n, active),
      ],
    );
  }

  Widget _composerSurface(AppLocalizations l10n, bool active) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: WtmColors.bg,
        border: Border(top: BorderSide(color: WtmColors.lineSoft)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          WtmSpace.s10,
          WtmSpace.screenH,
          WtmSpace.s10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    enabled: active,
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 500,
                    style: WtmType.body,
                    cursorColor: WtmColors.gold,
                    onSubmitted: active ? _send : null,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      counterText: '',
                      hintText: l10n.wtmChatComposerHint,
                      hintStyle: WtmType.sub,
                      fillColor: WtmColors.panel,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: WtmSpace.s12,
                        vertical: WtmSpace.s12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(WtmRadius.button),
                        borderSide: const BorderSide(color: WtmColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(WtmRadius.button),
                        borderSide: const BorderSide(color: WtmColors.gold),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(WtmRadius.button),
                        borderSide: const BorderSide(color: WtmColors.lineSoft),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: WtmSpace.s10),
                Semantics(
                  button: true,
                  enabled: active,
                  label: l10n.wtmChatSendLabel,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onTap: active ? () => _send(_composer.text) : null,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: active ? WtmGradients.cta : null,
                          color: active ? null : WtmColors.ghostBg,
                          shape: BoxShape.circle,
                          boxShadow: active ? WtmShadows.cta : null,
                        ),
                        alignment: Alignment.center,
                        child: WtmIcon(
                          WtmGlyph.chevron,
                          size: 18,
                          color: active ? WtmColors.ctaText : WtmColors.faint,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── pieces ─────────────────────────────────────────────────────────────────

/// The board `.navhead` (back · serif title + eyebrow · menu) — WtmPage's
/// chrome, inlined so the chat can own its column layout underneath.
class _NavHead extends StatelessWidget {
  const _NavHead({required this.title, required this.eyebrow, this.onMenu});

  final String title;
  final String eyebrow;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WtmSpace.screenH,
        WtmSpace.s8,
        WtmSpace.screenH,
        WtmSpace.s8,
      ),
      child: Row(
        children: [
          WtmIconButton(
            WtmGlyph.back,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => wtmPageBack(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.h2.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  eyebrow.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.eyebrow.copyWith(letterSpacing: 2.52),
                ),
              ],
            ),
          ),
          if (onMenu != null)
            WtmIconButton(
              WtmGlyph.dots,
              semanticLabel: MaterialLocalizations.of(context).showMenuTooltip,
              onTap: onMenu,
            )
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.glyph,
    required this.color,
    required this.background,
    required this.border,
    required this.text,
  });

  final WtmGlyph glyph;
  final Color color;
  final Color background;
  final Color border;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s12,
        vertical: WtmSpace.s8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          WtmIcon(glyph, size: 14, color: color),
          const SizedBox(width: WtmSpace.s8),
          Expanded(
            child: Text(text, style: WtmType.label.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// Compact pickup-plan card: general area · public landmark · time slot, with
/// Proposed/Confirmed state. Coarse public-place info only — never an address.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.chat,
    required this.l10n,
    this.onEdit,
    this.onConfirm,
  });

  final GiveawayPickupChat chat;
  final AppLocalizations l10n;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final parts = [
      chat.planArea,
      chat.planLandmark,
      chat.planTimeSlot,
    ].whereType<String>().where((s) => s.isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: EyebrowLabel(l10n.wtmChatPlanTitle)),
              if (chat.hasPlan)
                GoldPill(
                  label: chat.planConfirmed
                      ? l10n.wtmChatPlanConfirmedPill
                      : l10n.wtmChatPlanProposedPill,
                ),
            ],
          ),
          const SizedBox(height: WtmSpace.s6),
          Text(
            parts.isEmpty ? l10n.wtmChatPlanNone : parts.join(' · '),
            style: parts.isEmpty ? WtmType.sub : WtmType.body,
          ),
          if (onEdit != null || onConfirm != null) ...[
            const SizedBox(height: WtmSpace.s8),
            Row(
              children: [
                if (onEdit != null)
                  GoldPill(label: l10n.wtmChatPlanEdit, onTap: onEdit),
                if (onEdit != null && onConfirm != null)
                  const SizedBox(width: WtmSpace.s8),
                if (onConfirm != null)
                  GoldPill(label: l10n.wtmChatPlanConfirm, onTap: onConfirm),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SafetyStrip extends StatelessWidget {
  const _SafetyStrip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: WtmIcon(WtmGlyph.shield, size: 12, color: WtmColors.gold),
          ),
          const SizedBox(width: WtmSpace.s6),
          Expanded(child: Text(text, style: WtmType.micro)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble.server(GiveawayChatMessage this.message, this.l10n)
    : pending = null,
      onRetry = null;

  const _MessageBubble.pending(
    _PendingMessage this.pending,
    this.l10n, {
    required VoidCallback this.onRetry,
  }) : message = null;

  final GiveawayChatMessage? message;
  final _PendingMessage? pending;
  final AppLocalizations l10n;
  final VoidCallback? onRetry;

  static String _hhmm(DateTime t) {
    final local = t.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // An app-authored event line ("request accepted", "pickup confirmed")
    // belongs to neither participant, so it is a TIMELINE NOTICE: centred, rule
    // on each side, no fill and no capsule.
    //
    // It used to be a gold-tinted rounded pill — pixel-for-pixel the app's
    // GoldPill and a near-twin of the quick-reply chips sitting a few dp below
    // it, which is exactly why an unsendable event read as something tappable.
    // Nothing about the message TYPE changed; only how it is drawn.
    final system = message?.isSystem ?? false;
    if (system) {
      return Semantics(
        // Named as an update so a screen reader never announces it as a
        // message from the other person.
        label:
            '${l10n.wtmChatSystemNotice}: '
            '${message?.body ?? l10n.giveawayChatSystemLabel}',
        child: ExcludeSemantics(
          child: Padding(
            key: const Key('wtm-chat-system-notice'),
            padding: const EdgeInsets.symmetric(vertical: WtmSpace.s10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(child: Divider(color: WtmColors.lineSoft)),
                Flexible(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WtmSpace.s10,
                    ),
                    child: Text(
                      message?.body ?? l10n.giveawayChatSystemLabel,
                      textAlign: TextAlign.center,
                      style: WtmType.micro.copyWith(
                        height: 1.45,
                        color: WtmColors.faint,
                      ),
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: WtmColors.lineSoft)),
              ],
            ),
          ),
        ),
      );
    }

    final mine = pending != null || (message?.isMine ?? false);
    final redacted = message?.bodyDeleted ?? false;
    final failed = pending?.failed ?? false;
    final body = pending?.body ?? message?.body;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s12,
        vertical: WtmSpace.s8,
      ),
      decoration: BoxDecoration(
        color: mine ? WtmColors.pillBg : null,
        gradient: mine ? null : WtmGradients.cardFill,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(WtmRadius.tile),
          topRight: const Radius.circular(WtmRadius.tile),
          bottomLeft: Radius.circular(mine ? WtmRadius.tile : 4),
          bottomRight: Radius.circular(mine ? 4 : WtmRadius.tile),
        ),
        border: Border.all(
          color: failed
              ? WtmColors.danger
              : (mine ? WtmColors.pillBorder : WtmColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            redacted ? l10n.wtmChatMessageRemoved : (body ?? ''),
            style: redacted
                ? WtmType.sub.copyWith(fontStyle: FontStyle.italic)
                : WtmType.body,
          ),
          const SizedBox(height: 2),
          Text(
            failed
                ? l10n.wtmChatRetry
                : (pending != null
                      ? _hhmm(pending!.at)
                      : _hhmm(message!.createdAt)),
            style: WtmType.micro.copyWith(
              color: failed ? WtmColors.danger : WtmColors.faint,
            ),
          ),
        ],
      ),
    );

    final positioned = Padding(
      padding: const EdgeInsets.only(bottom: WtmSpace.s8),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Opacity(
          opacity: pending != null && !failed ? 0.6 : 1,
          child: failed
              ? GestureDetector(onTap: onRetry, child: bubble)
              : bubble,
        ),
      ),
    );
    return positioned;
  }
}

class _PlanDraft {
  const _PlanDraft(this.area, this.landmark, this.timeSlot);
  final String? area;
  final String? landmark;
  final String? timeSlot;
}

/// Bottom-sheet editor for the pickup plan (3 fields, WTM inputs).
class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.chat, required this.l10n});

  final GiveawayPickupChat chat;
  final AppLocalizations l10n;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  late final _area = TextEditingController(text: widget.chat.planArea ?? '');
  late final _landmark = TextEditingController(
    text: widget.chat.planLandmark ?? '',
  );
  late final _time = TextEditingController(
    text: widget.chat.planTimeSlot ?? '',
  );

  @override
  void dispose() {
    _area.dispose();
    _landmark.dispose();
    _time.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: WtmType.label.copyWith(color: WtmColors.muted)),
        const SizedBox(height: WtmSpace.s8),
        TextField(
          controller: controller,
          maxLines: 1,
          maxLength: 120,
          style: WtmType.body,
          cursorColor: WtmColors.gold,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            counterText: '',
            fillColor: WtmColors.bg2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: WtmSpace.s12,
              vertical: WtmSpace.s12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.gold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    String? clean(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            WtmSpace.s18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.wtmChatPlanTitle,
                textAlign: TextAlign.center,
                style: WtmType.h1.copyWith(fontSize: 20),
              ),
              const SizedBox(height: WtmSpace.s14),
              _field(l10n.wtmChatPlanArea, _area),
              const SizedBox(height: WtmSpace.s12),
              _field(l10n.wtmChatPlanLandmark, _landmark),
              const SizedBox(height: WtmSpace.s12),
              _field(l10n.wtmChatPlanTime, _time),
              const SizedBox(height: WtmSpace.s16),
              GradientCta(
                label: l10n.wtmChatPlanSave,
                onPressed: () => Navigator.of(
                  context,
                ).pop(_PlanDraft(clean(_area), clean(_landmark), clean(_time))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

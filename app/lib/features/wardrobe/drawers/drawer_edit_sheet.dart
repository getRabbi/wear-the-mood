import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import 'closet_drawer.dart';
import 'drawer_store.dart';

/// Create or edit a drawer (name + icon + accent color). Returns the saved
/// drawer, or null if dismissed.
Future<ClosetDrawer?> showDrawerEditSheet(
  BuildContext context, {
  ClosetDrawer? existing,
}) {
  return showModalBottomSheet<ClosetDrawer>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _DrawerEditSheet(existing: existing),
  );
}

class _DrawerEditSheet extends ConsumerStatefulWidget {
  const _DrawerEditSheet({this.existing});

  final ClosetDrawer? existing;

  @override
  ConsumerState<_DrawerEditSheet> createState() => _DrawerEditSheetState();
}

class _DrawerEditSheetState extends ConsumerState<_DrawerEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late DrawerIconKind _icon = widget.existing?.iconKind ?? DrawerIconKind.drawer;
  late int _accent =
      widget.existing?.accentValue ?? drawerAccentPalette.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.drawerNameRequired);
      return;
    }
    final store = ref.read(closetDrawersProvider.notifier);
    final ClosetDrawer result;
    if (widget.existing != null) {
      store.update(
        widget.existing!.id,
        name: name,
        iconKind: _icon,
        accentValue: _accent,
      );
      result = store.byId(widget.existing!.id)!;
    } else {
      result = store.create(name: name, iconKind: _icon, accentValue: _accent);
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final editing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpace.lg),
                  decoration: BoxDecoration(
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(_accent).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(_icon.data, color: Color(_accent)),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Text(
                    editing ? l10n.drawerEditTitle : l10n.drawerCreateTitle,
                    style: text.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Text(l10n.drawerNameLabel, style: text.labelLarge),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: l10n.drawerNameHint,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(l10n.drawerIconLabel, style: text.labelLarge),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final kind in DrawerIconKind.values)
                    _IconChoice(
                      icon: kind.data,
                      selected: kind == _icon,
                      accent: Color(_accent),
                      onTap: () => setState(() => _icon = kind),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Text(l10n.drawerColorLabel, style: text.labelLarge),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.md,
                runSpacing: AppSpace.sm,
                children: [
                  for (final value in drawerAccentPalette)
                    _ColorChoice(
                      value: value,
                      selected: value == _accent,
                      onTap: () => setState(() => _accent = value),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              PrimaryButton(
                label: l10n.drawerSave,
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : AppColors.glassFill,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? accent : AppColors.glassBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Icon(icon, size: 20, color: selected ? accent : AppColors.graphite),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(value);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

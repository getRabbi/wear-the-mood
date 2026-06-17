import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'closet_drawer.dart';
import 'drawer_edit_sheet.dart';
import 'drawer_store.dart';

/// A polished, mid-height drawer picker (real-device polish — the old sheet went
/// full-screen and had to be dragged down). Opens around ~55% of the screen with
/// a drag handle + title, is draggable/scrollable for long drawer lists, shows a
/// checkmark on the selected drawer, offers search when there are many drawers,
/// and a "Create new drawer" row. Returns the chosen drawer id, or null if
/// dismissed.
Future<String?> showDrawerPickerSheet(
  BuildContext context, {
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => _DrawerPickerSheet(selectedId: selectedId),
  );
}

class _DrawerPickerSheet extends ConsumerStatefulWidget {
  const _DrawerPickerSheet({this.selectedId});

  final String? selectedId;

  @override
  ConsumerState<_DrawerPickerSheet> createState() => _DrawerPickerSheetState();
}

class _DrawerPickerSheetState extends ConsumerState<_DrawerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final drawers = ref.watch(closetDrawersProvider);
    // Search only earns its keep once the list is long enough to scroll past.
    final showSearch = drawers.length > 6;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? drawers
        : drawers.where((d) => d.name.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.xs,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.drawerMoveTitle, style: text.titleMedium),
                  if (showSearch) ...[
                    const SizedBox(height: AppSpace.sm),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: l10n.drawerSearchHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.only(bottom: AppSpace.lg),
                children: [
                  for (final d in filtered)
                    ListTile(
                      leading: Icon(d.icon, color: d.accent),
                      title: Text(d.name),
                      trailing: d.id == widget.selectedId
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.accent,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(d.id),
                    ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Text(
                        l10n.drawerSearchEmpty,
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppColors.lavender,
                    ),
                    title: Text(l10n.wardrobeCreateDrawer),
                    onTap: () async {
                      final created = await showDrawerEditSheet(context);
                      if (created != null && context.mounted) {
                        Navigator.of(context).pop(created.id);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience for callers that have a [ClosetDrawer] id and want the drawer.
ClosetDrawer? drawerById(List<ClosetDrawer> drawers, String? id) {
  if (id == null) return null;
  for (final d in drawers) {
    if (d.id == id) return d;
  }
  return null;
}

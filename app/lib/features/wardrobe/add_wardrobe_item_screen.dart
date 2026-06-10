import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'wardrobe_image_service.dart';
import 'wardrobe_providers.dart';

/// Adds a piece to the closet (CLAUDE.md §8). Capture/pick a photo → it's
/// compressed (EXIF stripped) and uploaded to Supabase Storage → `POST
/// /v1/wardrobe` saves the item. Background removal + auto-tagging (§2.2) layer
/// on server-side later; for now the photo + optional name/category are enough.
class AddWardrobeItemScreen extends ConsumerStatefulWidget {
  const AddWardrobeItemScreen({super.key});

  @override
  ConsumerState<AddWardrobeItemScreen> createState() =>
      _AddWardrobeItemScreenState();
}

class _AddWardrobeItemScreenState extends ConsumerState<AddWardrobeItemScreen> {
  final _nameController = TextEditingController();
  Uint8List? _bytes;
  String? _category;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<({String value, String label})> _categories(AppLocalizations l10n) => [
    (value: 'Tops', label: l10n.addItemCatTops),
    (value: 'Bottoms', label: l10n.addItemCatBottoms),
    (value: 'Outerwear', label: l10n.addItemCatOuterwear),
    (value: 'Shoes', label: l10n.addItemCatShoes),
    (value: 'Accessories', label: l10n.addItemCatAccessories),
  ];

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await ref
          .read(wardrobeImageServiceProvider)
          .pickAndCompress(source);
      if (bytes != null && mounted) setState(() => _bytes = bytes);
    } catch (_) {
      _snack(l10n.addItemPickError);
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final url = await ref.read(wardrobeImageServiceProvider).upload(bytes);
      final name = _nameController.text.trim();
      await ref
          .read(wardrobeRepositoryProvider)
          .addItem(
            title: name.isEmpty ? null : name,
            category: _category,
            imageUrl: url,
          );
      ref.invalidate(wardrobeItemsProvider);
      if (!mounted) return;
      _snack(l10n.addItemSaved);
      context.pop();
    } on ApiException {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.addItemError);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.addItemError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bytes = _bytes;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addItemTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    children: [
                      _PhotoArea(
                        bytes: bytes,
                        onCamera: () => _pick(ImageSource.camera),
                        onGallery: () => _pick(ImageSource.gallery),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      TextField(
                        controller: _nameController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.addItemNameLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        l10n.addItemCategoryLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.sm,
                        children: [
                          for (final c in _categories(l10n))
                            ChoiceChip(
                              label: Text(c.label),
                              selected: _category == c.value,
                              onSelected: (sel) => setState(
                                () => _category = sel ? c.value : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _BottomBar(
                  child: PrimaryButton(
                    label: l10n.addItemSave,
                    icon: Icons.add_rounded,
                    isLoading: _busy,
                    onPressed: bytes == null ? null : _save,
                  ),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoArea extends StatelessWidget {
  const _PhotoArea({
    required this.bytes,
    required this.onCamera,
    required this.onGallery,
  });

  final Uint8List? bytes;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = bytes;

    if (data == null) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_a_photo_outlined,
                size: 40,
                color: AppColors.graphite,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                l10n.addItemChoosePhoto,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.addItemCamera),
                  ),
                  const SizedBox(width: AppSpace.md),
                  OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.addItemGallery),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Image.memory(data, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: onCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.addItemCamera),
            ),
            TextButton.icon(
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.addItemGallery),
            ),
          ],
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: child,
        ),
      ),
    );
  }
}

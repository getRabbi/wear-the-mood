import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The ONE signature-gradient call-to-action per screen — the hero/primary
/// action (gradient discipline, §3). Pill, 52dp, white label, optional leading
/// icon + loading state. Everything else uses [AccentButton] or [GhostButton].
class HeroButton extends StatelessWidget {
  const HeroButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      label: label,
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: enabled ? 1 : 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.signatureGradient,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: enabled ? AppShadow.accentGlow : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                height: 52,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : _Label(label: label, icon: icon, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A solid-accent primary action that is NOT the screen hero (e.g. "Save
/// changes"). Pill, 52dp, white label — disciplined, no gradient (§3).
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      label: label,
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : _Label(label: label, icon: icon, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lower-emphasis secondary action — transparent fill, 1px accent border, accent
/// label + icon. Use for secondary CTAs and the many per-card "Try on" buttons
/// (which must NOT be gradients, §3). [dense] gives a compact height for cards.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.dense = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool dense;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      label: label,
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: Container(
              height: dense ? 38 : 50,
              width: expand ? double.infinity : null,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: dense ? AppSpace.md : AppSpace.lg),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AppColors.accent, width: 1.2),
              ),
              child: _Label(
                label: label,
                icon: icon,
                color: AppColors.accent,
                size: dense ? 13 : 14.5,
                iconSize: dense ? 16 : 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared icon + label row for the button kit.
class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.color,
    this.icon,
    this.size = 15,
    this.iconSize = 20,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: AppSpace.sm),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

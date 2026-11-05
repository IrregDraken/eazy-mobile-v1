import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';

/// Eazy Assist launcher. It collapses to a narrow edge tab when parked.
class EazyAssistFab extends StatelessWidget {
  const EazyAssistFab({super.key, this.parked = true});

  final bool parked;

  @override
  Widget build(BuildContext context) {
    final accent = context.eazyAccent;
    final onAccent = context.eazyOnAccent;

    return Semantics(
      button: true,
      label: 'Open Eazy Assist',
      child: Tooltip(
        message: 'Open Eazy Assist',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: parked ? 56 : 64,
          height: parked ? 58 : 64,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(parked ? 30 : 32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(accent, Colors.white, .22)!,
                accent,
                Color.lerp(accent, Colors.black, .18)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .34),
                blurRadius: parked ? 14 : 20,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .13),
                blurRadius: 9,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.push('/assist'),
              child: Center(
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: onAccent,
                  size: parked ? 25 : 29,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

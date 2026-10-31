import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';

/// Floating Eazy Assist launcher for general, non-transactional app screens.
class EazyAssistFab extends StatelessWidget {
  const EazyAssistFab({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Tooltip(
      message: 'Open Eazy Assist',
      child: Material(
        color: context.eazyAccent,
        elevation: 16,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push('/assist'),
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  context.eazyAccent,
                  context.eazyAccent.withValues(alpha: .82),
                ],
              ),
              border: Border.all(
                color: context.eazyOnAccent.withValues(alpha: .45),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: context.eazyAccent.withValues(alpha: .36),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Image.asset(
              'assets/images/eazy_logo_mark.png',
              width: 31,
              height: 31,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.auto_awesome_rounded,
                color: context.eazyOnAccent,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';

/// Floating, layered Eazy Assist launcher for general app screens.
class EazyAssistFab extends StatelessWidget {
  const EazyAssistFab({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = context.eazyAccent;
    final onAccent = context.eazyOnAccent;

    return SafeArea(
      child: Tooltip(
        message: 'Open Eazy Assist',
        child: Semantics(
          button: true,
          label: 'Open Eazy Assist',
          child: SizedBox(
            width: 72,
            height: 78,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 9,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: .22),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .30),
                          blurRadius: 24,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.push('/assist'),
                    child: Ink(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(accent, Colors.white, .30)!,
                            accent,
                            Color.lerp(accent, Colors.black, .24)!,
                          ],
                          stops: const [0, .48, 1],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .62),
                          width: 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: .34),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                          const BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 7,
                            offset: Offset(0, 3),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: .38),
                            blurRadius: 2,
                            offset: const Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Image.asset(
                          'assets/images/eazy_logo_mark.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.auto_awesome_rounded,
                            color: onAccent,
                            size: 29,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: context.eazyOnAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 2),
                    ),
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

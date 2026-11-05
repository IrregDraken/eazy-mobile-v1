import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/ui/eazy_assist_fab.dart';
import '../chat/chat_page.dart';
import '../marketplace/marketplace_page.dart';
import '../profile/profile_page.dart';
import '../social/social_page.dart';
import '../wallet/wallet_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.auth,
    this.initialTab,
    this.initialAction,
    this.initialUsername,
    this.initialConversationId,
  });

  final AuthController auth;
  final String? initialTab;
  final String? initialAction;
  final String? initialUsername;
  final String? initialConversationId;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final _assistStorage = const FlutterSecureStorage();
  double? _assistLeft;
  double? _assistTop;
  bool _assistParked = true;
  bool _assistDockedRight = true;
  int unreadChats = 0;
  int unreadWallet = 0;
  int unreadNotifications = 0;
  bool loadingBadges = false;

  @override
  void initState() {
    super.initState();
    index = switch (widget.initialTab) {
      'shop' => 1,
      'wallet' => 2,
      'chat' => 3,
      'profile' => 4,
      _ => 0,
    };
    _restoreAssistPosition();
    _loadBadgeCounts();
  }

  Future<void> _loadBadgeCounts() async {
    if (loadingBadges) return;
    loadingBadges = true;
    try {
      final results = await Future.wait([
        widget.auth.api.get('chat/conversations?page=1&limit=50', auth: true),
        widget.auth.api.get('notifications?page=1&limit=100', auth: true),
      ]);
      final chats = (results[0]['items'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry));
      final notifications = (results[1]['items'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final chatCount = chats.fold<int>(
        0,
        (total, chat) =>
            total + (int.tryParse((chat['unreadCount'] ?? 0).toString()) ?? 0),
      );
      final walletCount = notifications.where((item) {
        final type = item['type']?.toString().toLowerCase() ?? '';
        return item['isRead'] != true &&
            const {'payment', 'order'}.contains(type);
      }).length;
      final notificationCount = notifications
          .where((item) => item['isRead'] != true)
          .length;
      if (mounted) {
        setState(() {
          unreadChats = chatCount;
          unreadWallet = walletCount;
          unreadNotifications = notificationCount;
        });
      }
    } catch (_) {
      // Badge counters are supplemental; never block the primary navigation.
    } finally {
      loadingBadges = false;
    }
  }

  int _badgeForDestination(int destinationIndex) => switch (destinationIndex) {
        2 => unreadWallet,
        3 => unreadChats,
        _ => 0,
      };

  Widget _notificationCountBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Positioned(
      right: -7,
      top: -6,
      child: Container(
        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          count > 99 ? '99+' : count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Future<void> _restoreAssistPosition() async {
    try {
      final left = double.tryParse(
        await _assistStorage.read(key: 'eazy.assist.left') ?? '',
      );
      final top = double.tryParse(
        await _assistStorage.read(key: 'eazy.assist.top') ?? '',
      );
      final edge = await _assistStorage.read(key: 'eazy.assist.edge');
      if (mounted) {
        setState(() {
          _assistLeft = left;
          _assistTop = top;
          _assistDockedRight = edge != 'left';
          _assistParked = true;
        });
      }
    } catch (_) {
      // Keep the default right-edge dock if saved position cannot be read.
    }
  }

  Future<void> _saveAssistPosition() async {
    try {
      if (_assistLeft != null && _assistTop != null) {
        await _assistStorage.write(
          key: 'eazy.assist.left',
          value: _assistLeft.toString(),
        );
        await _assistStorage.write(
          key: 'eazy.assist.top',
          value: _assistTop.toString(),
        );
        await _assistStorage.write(
          key: 'eazy.assist.edge',
          value: _assistDockedRight ? 'right' : 'left',
        );
      }
    } catch (_) {
      // Edge docking still works for this session if persistence is unavailable.
    }
  }

  late final pages = <Widget>[
    SocialPage(
      auth: widget.auth,
      openComposerOnStart: widget.initialAction == 'create',
    ),
    const MarketplacePage(),
    const WalletPage(),
    ChatPage(
      initialUsername: widget.initialUsername,
      initialConversationId: widget.initialConversationId,
    ),
    ProfilePage(auth: widget.auth),
  ];

  Widget _navigationDestination({
    required int destinationIndex,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final selected = index == destinationIndex;
    final accent = context.eazyAccent;
    final textColor = selected ? accent : context.eazyMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            setState(() => index = destinationIndex);
            _loadBadgeCounts();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: selected ? 48 : 42,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: .17)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: .13),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ]
                        : const [],
                  ),
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            selected ? selectedIcon : icon,
                            key: ValueKey<bool>(selected),
                            size: selected ? 23 : 22,
                            color: textColor,
                          ),
                        ),
                        _notificationCountBadge(_badgeForDestination(destinationIndex)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    height: 1.05,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  ),
                  child: Text(label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidGlassNavigation() {
    final accent = context.eazyAccent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    surface.withValues(alpha: isDark ? .78 : .76),
                    accent.withValues(alpha: isDark ? .16 : .11),
                    surface.withValues(alpha: isDark ? .72 : .70),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? .13 : .48),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: isDark ? .10 : .14),
                    blurRadius: 28,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? .20 : .07),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _navigationDestination(
                    destinationIndex: 0,
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                  ),
                  _navigationDestination(
                    destinationIndex: 1,
                    icon: Icons.storefront_outlined,
                    selectedIcon: Icons.storefront_rounded,
                    label: 'Discover',
                  ),
                  _navigationDestination(
                    destinationIndex: 2,
                    icon: Icons.account_balance_wallet_outlined,
                    selectedIcon: Icons.account_balance_wallet_rounded,
                    label: 'Wallet',
                  ),
                  _navigationDestination(
                    destinationIndex: 3,
                    icon: Icons.chat_bubble_outline_rounded,
                    selectedIcon: Icons.chat_bubble_rounded,
                    label: 'Chat',
                  ),
                  _navigationDestination(
                    destinationIndex: 4,
                    icon: Icons.person_outline_rounded,
                    selectedIcon: Icons.person_rounded,
                    label: 'You',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final mediaPadding = MediaQuery.paddingOf(context);
        final controlHeight = _assistParked ? 58.0 : 64.0;
        final minimumTop = mediaPadding.top + 12;
        final maximumTop = (constraints.maxHeight -
                mediaPadding.bottom -
                96 -
                controlHeight)
            .clamp(minimumTop, constraints.maxHeight - controlHeight)
            .toDouble();
        final savedTop = _assistTop ?? constraints.maxHeight * .52;
        final top = savedTop.clamp(minimumTop, maximumTop).toDouble();
        final defaultLeft =
            (constraints.maxWidth - 72).clamp(8.0, constraints.maxWidth - 64).toDouble();
        final parkedLeft = _assistDockedRight
            ? constraints.maxWidth - 26
            : -30.0;
        final expandedLeft = (_assistLeft ?? defaultLeft)
            .clamp(8.0, constraints.maxWidth - 72)
            .toDouble();
        final left = _assistParked ? parkedLeft : expandedLeft;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final showAssist =
            (index == 0 || index == 1 || index == 4) && !keyboardOpen;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IndexedStack(index: index, children: pages),
            if (showAssist)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: left,
                top: top,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {
                    setState(() {
                      _assistParked = false;
                      _assistLeft = _assistDockedRight
                          ? constraints.maxWidth - 64
                          : 0;
                      _assistTop = top;
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _assistLeft = ((_assistLeft ?? defaultLeft) +
                              details.delta.dx)
                          .clamp(8.0, constraints.maxWidth - 72)
                          .toDouble();
                      _assistTop = ((_assistTop ?? top) + details.delta.dy)
                          .clamp(
                            minimumTop,
                            (constraints.maxHeight -
                                    mediaPadding.bottom -
                                    96 -
                                    64)
                                .clamp(minimumTop, constraints.maxHeight - 64)
                                .toDouble(),
                          )
                          .toDouble();
                    });
                  },
                  onPanEnd: (_) {
                    final currentLeft = _assistLeft ?? defaultLeft;
                    setState(() {
                      _assistDockedRight =
                          currentLeft + 32 >= constraints.maxWidth / 2;
                      _assistLeft = _assistDockedRight
                          ? constraints.maxWidth - 28
                          : -28;
                      _assistParked = true;
                    });
                    _saveAssistPosition();
                  },
                  child: EazyAssistFab(parked: _assistParked),
                ),
              ),
          ],
        );
      },
    ),
    bottomNavigationBar: _buildLiquidGlassNavigation(),
  );

}

class EazyPageHeader extends StatelessWidget {
  const EazyPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(color: context.eazyMuted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

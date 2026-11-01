import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  const HomeShell({super.key, required this.auth, this.initialTab, this.initialAction});
  final AuthController auth;
  final String? initialTab;
  final String? initialAction;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final _assistStorage = const FlutterSecureStorage();
  double? _assistLeft;
  double? _assistTop;
  bool _assistVisible = true;

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
  }

  Future<void> _restoreAssistPosition() async {
    try {
      final left = double.tryParse(
        await _assistStorage.read(key: 'eazy.assist.left') ?? '',
      );
      final top = double.tryParse(
        await _assistStorage.read(key: 'eazy.assist.top') ?? '',
      );
      if (mounted && left != null && top != null) {
        setState(() {
          _assistLeft = left;
          _assistTop = top;
        });
      }
    } catch (_) {
      // The launcher remains usable at its default position.
    }
  }

  Future<void> _saveAssistPosition() async {
    try {
      if (_assistLeft != null && _assistTop != null) {
        await _assistStorage.write(key: 'eazy.assist.left', value: _assistLeft.toString());
        await _assistStorage.write(key: 'eazy.assist.top', value: _assistTop.toString());
      }
    } catch (_) {
      // Position persistence is best-effort.
    }
  }
  late final pages = <Widget>[
    SocialPage(auth: widget.auth, openComposerOnStart: widget.initialAction == 'create'),
    const MarketplacePage(),
    const WalletPage(),
    const ChatPage(),
    ProfilePage(auth: widget.auth),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final defaultLeft = (constraints.maxWidth - 88).clamp(8.0, constraints.maxWidth - 80).toDouble();
        final defaultTop = (constraints.maxHeight - 170).clamp(8.0, constraints.maxHeight - 160).toDouble();
        final left = (_assistLeft ?? defaultLeft).clamp(8.0, constraints.maxWidth - 80).toDouble();
        final top = (_assistTop ?? defaultTop).clamp(8.0, constraints.maxHeight - 160).toDouble();
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final showAssist = (index == 0 || index == 1 || index == 4) &&
            _assistVisible &&
            !keyboardOpen;
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle) {
                  final shouldShow = notification.direction == ScrollDirection.forward;
                  if (_assistVisible != shouldShow) {
                    setState(() => _assistVisible = shouldShow);
                  }
                }
                return false;
              },
              child: IndexedStack(index: index, children: pages),
            ),
            if (showAssist)
              Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _assistLeft = (left + details.delta.dx).clamp(8.0, constraints.maxWidth - 80).toDouble();
                      _assistTop = (top + details.delta.dy).clamp(8.0, constraints.maxHeight - 160).toDouble();
                    });
                  },
                  onPanEnd: (_) => _saveAssistPosition(),
                  child: const EazyAssistFab(),
                ),
              ),
          ],
        );
      },
    ),
    bottomNavigationBar: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Wallet',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'You',
            ),
          ],
        ),
      ),
    ),
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

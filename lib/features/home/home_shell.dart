import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../chat/chat_page.dart';
import '../marketplace/marketplace_page.dart';
import '../profile/profile_page.dart';
import '../social/social_page.dart';
import '../wallet/wallet_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.auth, this.initialTab});
  final AuthController auth;
  final String? initialTab;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
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
  }

  late final pages = <Widget>[
    SocialPage(auth: widget.auth),
    const MarketplacePage(),
    const WalletPage(),
    const ChatPage(),
    ProfilePage(auth: widget.auth),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: Stack(
      children: [
        IndexedStack(index: index, children: pages),
        if (index != 3)
          Positioned(
            right: 16,
            bottom: 90,
            child: SafeArea(
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
            ),
          ),
      ],
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
                  style: const TextStyle(color: EazyColors.muted),
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

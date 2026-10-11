import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/support/support_faq.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final question = TextEditingController();
  String? answer;

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> contact(String address, String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      queryParameters: {'subject': subject},
    );
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app is available on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Help & support')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            const Text(
              'Find a safe answer first, then contact the right Eazy channel if you still need help.',
              style: TextStyle(color: EazyColors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.forum_outlined, color: EazyColors.blue),
                title: const Text('Live Chat Coming Soon', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Live agent chat is not available yet.'),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Ask Eazy Help', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            TextField(
              controller: question,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => setState(() => answer = supportReplyFor(question.text)),
              decoration: InputDecoration(
                hintText: 'e.g. My verification code did not arrive',
                suffixIcon: IconButton(
                  tooltip: 'Find an answer',
                  onPressed: () => setState(() => answer = supportReplyFor(question.text)),
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (answer != null) ...[
              const SizedBox(height: 12),
              Card(
                color: EazyColors.surfaceRaised,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(answer!, style: const TextStyle(height: 1.45)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text('Frequently asked questions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            ...supportFaqs.map(
              (faq) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text(faq.question, style: const TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [Text(faq.answer, style: const TextStyle(color: EazyColors.muted, height: 1.45))],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Escalate a case', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'Email channels are shown for routing only. The operator must configure and verify inbound mailboxes or forwarding before launch. Do not include passwords, verification codes, tokens, PINs or full payment credentials.',
              style: TextStyle(color: EazyColors.muted, height: 1.45),
            ),
            const SizedBox(height: 10),
            _ContactTile(
              icon: Icons.support_agent_rounded,
              title: 'General support',
              address: 'support@eazy.name.ng',
              onTap: () => contact('support@eazy.name.ng', 'Eazy support request'),
            ),
            _ContactTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Payment or transfer dispute',
              address: 'support@eazy.name.ng',
              onTap: () => contact('support@eazy.name.ng', 'Eazy payment or transfer dispute'),
            ),
            _ContactTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy or deletion request',
              address: 'privacy@eazy.name.ng',
              onTap: () => contact('privacy@eazy.name.ng', 'Eazy privacy or deletion request'),
            ),
            _ContactTile(
              icon: Icons.security_outlined,
              title: 'Security report',
              address: 'security@eazy.name.ng',
              onTap: () => contact('security@eazy.name.ng', 'Eazy security report'),
            ),
          ],
        ),
      );
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.title, required this.address, required this.onTap});
  final IconData icon;
  final String title;
  final String address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: EazyColors.green),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(address),
          trailing: const Icon(Icons.mail_outline_rounded),
          onTap: onTap,
        ),
      );
}

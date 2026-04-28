import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

/// Ported from SD-lib `CustomerHelpView` (layout preserved, theme-adapted).
class HelpSupportView extends StatelessWidget {
  const HelpSupportView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "Help & Support",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton.filledTonal(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildContactSection(theme),
            const SizedBox(height: 32),
            Text(
              "Frequently Asked Questions",
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            _buildFAQTile(
              theme,
              "How do I track my order?",
              "You can track your order in the 'Order History' section of your profile.",
            ),
            _buildFAQTile(
              theme,
              "What payment methods are accepted?",
              "We accept credit/debit cards and cash on delivery.",
            ),
            _buildFAQTile(
              theme,
              "Can I cancel my order?",
              "Orders can be cancelled within 5 minutes of placing them.",
            ),
            _buildFAQTile(
              theme,
              "How to change delivery address?",
              "Go to 'My Addresses' in your profile to update or add new locations.",
            ),
          ],
        ),
      ),
      floatingActionButton: const Padding(
        padding: EdgeInsets.only(right: 8, bottom: 8),
        child: CustomerVoiceMicRow(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildContactSection(ThemeData theme) {
    return Column(
      children: [
        _buildContactCard(
          theme,
          "Chat with us",
          "Average response time: 2 mins",
          Icons.chat_bubble_outline_rounded,
          Colors.blue,
        ),
        const SizedBox(height: 16),
        _buildContactCard(
          theme,
          "Call Support",
          "Available 24/7",
          Icons.phone_in_talk_outlined,
          Colors.green,
        ),
      ],
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildContactCard(
    ThemeData theme,
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration:
                BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildFAQTile(ThemeData theme, String question, String answer) {
    return ExpansionTile(
      title: Text(
        question,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: theme.colorScheme.onSurface,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            answer,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(side: BorderSide.none),
    ).animate().fadeIn(delay: 200.ms);
  }
}


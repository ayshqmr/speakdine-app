import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Ported from SD-lib `RestaurantSupportView` (layout preserved, theme-adapted).
class MerchantSupportView extends StatelessWidget {
  const MerchantSupportView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "Merchant Support",
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEmergencyCard(theme),
            const SizedBox(height: 32),
            Text(
              "Support Channels",
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            _buildChannelTile(
              theme,
              "Merchant Help Center",
              Icons.menu_book_rounded,
              "Guides on using the platform",
              () {},
            ),
            _buildChannelTile(
              theme,
              "Payout Issues",
              Icons.account_balance_wallet_rounded,
              "Resolution for payment delays",
              () {},
            ),
            _buildChannelTile(
              theme,
              "Order Disputes",
              Icons.report_problem_rounded,
              "Report issues with specific orders",
              () {},
            ),
            _buildChannelTile(
              theme,
              "Tech Support",
              Icons.biotech_rounded,
              "Report app bugs or hardware issues",
              () {},
            ),
            const SizedBox(height: 40),
            _buildEmailSupport(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyCard(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 16),
          const Text(
            "Live Merchant Support",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Connect with a merchant specialist for immediate assistance with active orders.",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "START LIVE CHAT",
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(duration: 400.ms, curve: Curves.easeOutBack);
  }

  Widget _buildChannelTile(
    ThemeData theme,
    String title,
    IconData icon,
    String description,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
    ).animate().fadeIn().slideX(begin: 0.05);
  }

  Widget _buildEmailSupport(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          Text(
            "Prefer email?",
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "merchants@speakdine.com",
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}


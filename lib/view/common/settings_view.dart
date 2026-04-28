import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speak_dine/widgets/customer_voice_fab.dart';

/// Ported from SD-lib `CustomerSettingsView` (layout preserved, theme-adapted).
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _notificationsEnabled = true;
  bool _locationSharing = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          "Settings",
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
          children: [
            _buildSection(
              theme,
              "Account Security",
              [
                _buildSettingTile(
                  theme,
                  "Change Password",
                  Icons.lock_outline_rounded,
                  () {},
                ),
                _buildSettingTile(
                  theme,
                  "Two-Factor Authentication",
                  Icons.security_rounded,
                  () {},
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              theme,
              "Preferences",
              [
                _buildSwitchTile(
                  theme,
                  "Push Notifications",
                  Icons.notifications_active_outlined,
                  _notificationsEnabled,
                  (v) => setState(() => _notificationsEnabled = v),
                ),
                _buildSwitchTile(
                  theme,
                  "Location Services",
                  Icons.location_on_outlined,
                  _locationSharing,
                  (v) => setState(() => _locationSharing = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              theme,
              "App Info",
              [
                _buildSettingTile(
                  theme,
                  "Terms of Service",
                  Icons.description_outlined,
                  () {},
                ),
                _buildSettingTile(
                  theme,
                  "Privacy Policy",
                  Icons.privacy_tip_outlined,
                  () {},
                ),
                _buildSettingTile(
                  theme,
                  "App Version",
                  Icons.info_outline_rounded,
                  () {},
                  trailing: const Text(
                    "1.0.0",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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

  Widget _buildSection(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
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
          child: Column(children: children),
        ),
      ],
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildSettingTile(
    ThemeData theme,
    String title,
    IconData icon,
    VoidCallback onTap, {
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: theme.colorScheme.primary, size: 24),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
    );
  }

  Widget _buildSwitchTile(
    ThemeData theme,
    String title,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      secondary: Icon(icon, color: theme.colorScheme.primary, size: 24),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: theme.colorScheme.onSurface,
        ),
      ),
      activeColor: theme.colorScheme.primary,
    );
  }
}


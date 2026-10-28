import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'about_screen.dart';
import 'app_settings_screen.dart';
import 'backup_screen.dart';
import 'extras_screen.dart';
import 'manual_screen.dart';
import 'rug_types_screen.dart';
import 'stats_screen.dart';
import 'support_screen.dart';
import 'users_screen.dart';

/// Razdelilnik. Nastavitve so bile prej en dolg zaslon — tu so razbite na
/// posamezne strani, da je vsaka stvar na svojem mestu.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PageHeader('Več'),
            const _GroupLabel('Poslovno'),
            _Group(
              rows: [
                MenuRow(
                  icon: Icons.straighten,
                  label: 'Mere in cena',
                  onTap: () => open(const RugTypesScreen()),
                ),
                MenuRow(
                  icon: Icons.local_offer_outlined,
                  label: 'Cenik',
                  onTap: () => open(const ExtrasScreen()),
                ),
                MenuRow(
                  icon: Icons.bar_chart,
                  label: 'Statistika in promet',
                  onTap: () => open(const StatsScreen()),
                ),
              ],
            ),
            const _GroupLabel('Upravljanje'),
            _Group(
              rows: [
                MenuRow(
                  icon: Icons.group_outlined,
                  label: 'Uporabniki',
                  onTap: () => open(const UsersScreen()),
                ),
                MenuRow(
                  icon: Icons.settings_outlined,
                  label: 'Nastavitve',
                  onTap: () => open(const AppSettingsScreen()),
                ),
                MenuRow(
                  icon: Icons.cloud_outlined,
                  label: 'Varnostne kopije',
                  onTap: () => open(const BackupScreen()),
                ),
              ],
            ),
            const _GroupLabel('Pomoč'),
            _Group(
              rows: [
                MenuRow(
                  icon: Icons.menu_book_outlined,
                  label: 'Navodila',
                  onTap: () => open(const ManualScreen()),
                ),
                MenuRow(
                  icon: Icons.support_agent,
                  label: 'Podpora',
                  onTap: () => open(const SupportScreen()),
                ),
                MenuRow(
                  icon: Icons.info_outline,
                  label: 'O aplikaciji',
                  onTap: () => open(const AboutScreen()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MenuGroup(rows: rows),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SectionHeader(text),
    );
  }
}

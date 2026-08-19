import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/home/presentation/home_screen.dart';
import 'package:scan2/features/home/presentation/tools_screen.dart';
import 'package:scan2/features/library/presentation/documents_view.dart';
import 'package:scan2/features/settings/presentation/settings_screen.dart';

/// The app shell: Home, Documents, a raised Scan button, Tools, Settings.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Brand.canvas,
      extendBody: true,
      drawer: _AppDrawer(
        selected: _tab,
        onSelect: (index) {
          Navigator.pop(context);
          setState(() => _tab = index);
        },
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
            onViewAllDocuments: () => setState(() => _tab = 1),
          ),
          const DocumentsView(),
          const ToolsScreen(),
          const SettingsScreen(embedded: true),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _ScanButton(
        onPressed: () => context.push('/camera'),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.09),
              blurRadius: 18,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: BottomAppBar(
          padding: EdgeInsets.zero,
          shape: const CircularNotchedRectangle(),
          notchMargin: 9,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.folder_outlined,
                  activeIcon: Icons.folder_rounded,
                  label: 'Documents',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ),
              const SizedBox(width: 78),
              Expanded(
                child: _NavItem(
                  icon: Icons.apps_outlined,
                  activeIcon: Icons.apps_rounded,
                  label: 'Tools',
                  selected: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: 'Settings',
                  selected: _tab == 3,
                  onTap: () => setState(() => _tab = 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: ScanellaWordmark(fontSize: BrandType.wordmarkCompact),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Scan. Save. Simplify.',
                style: BrandType.subtitle,
              ),
            ),
            _DrawerItem(
              icon: Icons.home_outlined,
              label: 'Home',
              selected: selected == 0,
              onTap: () => onSelect(0),
            ),
            _DrawerItem(
              icon: Icons.folder_outlined,
              label: 'Documents',
              selected: selected == 1,
              onTap: () => onSelect(1),
            ),
            _DrawerItem(
              icon: Icons.apps_outlined,
              label: 'Tools',
              selected: selected == 2,
              onTap: () => onSelect(2),
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              selected: selected == 3,
              onTap: () => onSelect(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: selected ? Brand.blue : Brand.ink),
      title: Text(
        label,
        style: BrandType.title.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Brand.blue : Brand.ink,
        ),
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4C7CFF), Brand.blue],
          ),
          boxShadow: [
            BoxShadow(
              color: Brand.blue.withValues(alpha: 0.30),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: const Center(
              child: Icon(
                Icons.photo_camera_rounded,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Brand.blue : Brand.grey;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? activeIcon : icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: BrandType.caption.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({required this.child, super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  static const _destinations = [
    _NavDestination(
      path: '/library',
      icon: CupertinoIcons.play_rectangle,
      selectedIcon: CupertinoIcons.play_rectangle_fill,
      label: '媒体库',
    ),
    _NavDestination(
      path: '/storages',
      icon: CupertinoIcons.folder,
      selectedIcon: CupertinoIcons.folder_fill,
      label: '资源库',
    ),
    _NavDestination(
      path: '/profile',
      icon: CupertinoIcons.person,
      selectedIcon: CupertinoIcons.person_fill,
      label: '我的',
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateIndexFromLocation();
  }

  void _updateIndexFromLocation() {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.path));
    if (index != -1 && index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  void _onDestinationSelected(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      context.go(_destinations[index].path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 0.5,
            thickness: 0.5,
            color: isDark ? Colors.grey[800] : Colors.grey[300],
          ),
          Container(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(_destinations.length, (index) {
                    final dest = _destinations[index];
                    final isSelected = index == _currentIndex;
                    return _NavItem(
                      icon: isSelected ? dest.selectedIcon : dest.icon,
                      label: dest.label,
                      isSelected: isSelected,
                      onTap: () => _onDestinationSelected(index),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDestination {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

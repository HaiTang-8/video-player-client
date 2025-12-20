import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 主页面容器，包含底部导航栏
class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({required this.child, super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  // 导航目的地配置
  static const _destinations = [
    _NavDestination(
      path: '/library',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: '媒体库',
    ),
    _NavDestination(
      path: '/storages',
      icon: Icons.storage_outlined,
      selectedIcon: Icons.storage,
      label: '资源库',
    ),
    _NavDestination(
      path: '/profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
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
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}

/// 导航目的地配置
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

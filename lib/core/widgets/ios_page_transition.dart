import 'package:flutter/material.dart';

const Duration _kTransitionDuration = Duration(milliseconds: 400);

class IosPageTransitionsBuilder extends PageTransitionsBuilder {
  const IosPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _IosSlideTransition(
      primaryAnimation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _IosSlideTransition extends StatelessWidget {
  const _IosSlideTransition({
    required this.primaryAnimation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> primaryAnimation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primaryPosition = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: primaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    final secondaryPosition = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0.0),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    return SlideTransition(
      position: secondaryPosition,
      child: SlideTransition(
        position: primaryPosition,
        child: child,
      ),
    );
  }
}

class IosTransitionPage<T> extends Page<T> {
  const IosTransitionPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    return _IosPageRouteImpl<T>(page: this);
  }
}

class _IosPageRouteImpl<T> extends PageRoute<T> {
  _IosPageRouteImpl({required IosTransitionPage<T> page}) : super(settings: page);

  IosTransitionPage<T> get _page => settings as IosTransitionPage<T>;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => _kTransitionDuration;

  @override
  Duration get reverseTransitionDuration => _kTransitionDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _page.child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _IosSlideTransition(
      primaryAnimation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

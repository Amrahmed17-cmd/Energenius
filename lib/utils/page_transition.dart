import 'package:flutter/material.dart';

class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  
  FadePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = 0.0;
            const end = 1.0;
            const curve = Curves.easeOut;
            
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var fadeAnimation = animation.drive(tween);
            
            return FadeTransition(
              opacity: fadeAnimation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 350),
          opaque: false,
          barrierDismissible: false,
        );
}

// Helper function to navigate with fade transition
void navigateWithFade(BuildContext context, Widget page) {
  Navigator.push(
    context,
    FadePageRoute(page: page),
  );
}

// Helper function to replace current screen with fade transition
void replaceWithFade(BuildContext context, Widget page) {
  Navigator.pushReplacement(
    context,
    FadePageRoute(page: page),
  );
} 
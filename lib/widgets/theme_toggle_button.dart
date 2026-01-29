import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import 'dart:math' as math;

class ThemeToggleButton extends StatefulWidget {
  final double width;
  final double height;
  final double iconSize;
  final Duration animationDuration;
  final BorderRadius? borderRadius;

  const ThemeToggleButton({
    super.key,
    this.width = 48.0, // compact width for icon toggle
    this.height = 48.0, // compact height for icon toggle
    this.iconSize = 28.0, // larger icon for visibility
    this.animationDuration = const Duration(milliseconds: 200),
    this.borderRadius,
  });

  @override
  State<ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<ThemeToggleButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _iconRotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _iconRotation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      if (themeProvider.isDarkTheme) {
        _controller.value = 1.0;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkTheme = themeProvider.isDarkTheme;
    return GestureDetector(
      onTap: () {
        if (isDarkTheme) {
          _controller.reverse();
        } else {
          _controller.forward();
        }
        themeProvider.toggleTheme(!isDarkTheme);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: widget.borderRadius ?? BorderRadius.circular(widget.height / 2),
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 1.0 - _iconRotation.value,
                  child: Icon(
                    Icons.wb_sunny_rounded,
                    color: isDarkTheme ? Colors.grey[400] : Colors.amber[700],
                    size: widget.iconSize,
                  ),
                ),
                Opacity(
                  opacity: _iconRotation.value,
                  child: Transform.rotate(
                    angle: 3.1416 * _iconRotation.value,
                    child: Icon(
                      Icons.nightlight_round,
                      color: isDarkTheme ? Colors.blue[200] : Colors.grey[600],
                      size: widget.iconSize,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
class PremiumCloudPainter extends CustomPainter {
  final Color color;
  
  PremiumCloudPainter(this.color);
  
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    
    // Create a more detailed cloud shape
    final baseHeight = size.height * 0.6;
    path.moveTo(size.width * 0.1, baseHeight);
    
    // First puff
    path.quadraticBezierTo(
      size.width * 0.1, size.height * 0.4,
      size.width * 0.25, size.height * 0.4
    );
    
    // Middle puff (larger)
    path.quadraticBezierTo(
      size.width * 0.35, size.height * 0.2,
      size.width * 0.5, size.height * 0.3
    );
    
    // Third puff
    path.quadraticBezierTo(
      size.width * 0.65, size.height * 0.25,
      size.width * 0.75, size.height * 0.4
    );
    
    // Last small puff
    path.quadraticBezierTo(
      size.width * 0.85, size.height * 0.35,
      size.width * 0.9, size.height * 0.5
    );
    
    // Close the cloud base
    path.lineTo(size.width * 0.9, baseHeight);
    path.close();
    
    // Draw cloud with a slight gradient
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color,
        color.withAlpha(192),
      ],
    );
    
    final gradientPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    
    canvas.drawPath(path, gradientPaint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SkyDetailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(16)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    
    // Add subtle horizontal cloud-like layers
    for (int i = 0; i < 4; i++) {
      final heightPos = size.height * (0.2 + i * 0.2);
      final path = Path();
      
      path.moveTo(0, heightPos);
      path.quadraticBezierTo(
        size.width * 0.2, heightPos - size.height * 0.05,
        size.width * 0.5, heightPos
      );
      path.quadraticBezierTo(
        size.width * 0.8, heightPos + size.height * 0.05,
        size.width, heightPos
      );
      path.lineTo(size.width, heightPos + size.height * 0.03);
      path.quadraticBezierTo(
        size.width * 0.8, heightPos + size.height * 0.08,
        size.width * 0.5, heightPos + size.height * 0.03
      );
      path.quadraticBezierTo(
        size.width * 0.2, heightPos - size.height * 0.02,
        0, heightPos + size.height * 0.03
      );
      path.close();
      
      canvas.drawPath(path, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LandscapePainter extends CustomPainter {
  final bool nightMode;
  final double transitionValue;
  
  LandscapePainter({required this.nightMode, required this.transitionValue});
  
  @override
  void paint(Canvas canvas, Size size) {
    // Create mountain silhouette
    final mountainPaint = Paint()
      ..color = nightMode 
          ? const Color(0xFF0A1526) 
          : const Color(0xFF2A5D77).withAlpha(204) // 0.8 opacity = 204/255
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    
    final path = Path();
    
    // Base
    path.moveTo(0, size.height);
    
    // First mountain
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width * 0.1, size.height * 0.3,
      size.width * 0.2, size.height * 0.6
    );
    
    // Middle mountains
    path.quadraticBezierTo(
      size.width * 0.3, size.height * 0.5,
      size.width * 0.4, size.height * 0.7
    );
    path.quadraticBezierTo(
      size.width * 0.5, size.height * 0.2,
      size.width * 0.6, size.height * 0.6
    );
    
    // Last mountain
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 0.4,
      size.width * 0.9, size.height * 0.7
    );
    path.quadraticBezierTo(
      size.width * 0.95, size.height * 0.8,
      size.width, size.height * 0.6
    );
    
    // Bottom edge
    path.lineTo(size.width, size.height);
    path.close();
    
    canvas.drawPath(path, mountainPaint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => 
    oldDelegate is LandscapePainter && 
    (oldDelegate.nightMode != nightMode || 
     oldDelegate.transitionValue != transitionValue);
}

class SunRaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rayCount = 12;
    final rayPaint = Paint()
      ..color = Colors.yellow.withAlpha(80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;

    for (int i = 0; i < rayCount; i++) {
      final angle = (i * (2 * math.pi / rayCount));
      final startPoint = Offset(
        center.dx + math.cos(angle) * (radius * 0.8),
        center.dy + math.sin(angle) * (radius * 0.8),
      );
      final endPoint = Offset(
        center.dx + math.cos(angle) * (radius * 1.1),
        center.dy + math.sin(angle) * (radius * 1.1),
      );
      
      canvas.drawLine(startPoint, endPoint, rayPaint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MoonCratersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(12); // Fixed seed for consistent craters
    final craterCount = 5;
    final craterPaint = Paint()
      ..color = Colors.grey[400]!.withAlpha(128)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    
    for (int i = 0; i < craterCount; i++) {
      final x = random.nextDouble() * size.width * 0.6 + size.width * 0.2;
      final y = random.nextDouble() * size.height * 0.6 + size.height * 0.2;
      final craterSize = random.nextDouble() * size.width * 0.15 + size.width * 0.05;
      
      canvas.drawCircle(Offset(x, y), craterSize, craterPaint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
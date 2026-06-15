import 'package:flutter/widgets.dart';

class FloatingGlow extends StatelessWidget{
  final Alignment alignment; 
  final double size; 
  final Color color; 

  const FloatingGlow({super.key, required this.alignment, required this.size, required this.color}); 

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle, 
          color: color.withOpacity(0.18),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.45), blurRadius: 15, spreadRadius: 40)
          ]
        ),
      ),
    );
  }
}
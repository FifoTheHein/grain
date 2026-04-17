import 'package:flutter/material.dart';

class ProjectCategory {
  final Color color;
  final Color tint;
  final String code;

  const ProjectCategory({
    required this.color,
    required this.tint,
    required this.code,
  });

  Map<String, dynamic> toJson() => {
        // toARGB32() is the forward-compatible replacement for deprecated Color.value
        'color': color.toARGB32(),
        'tint': tint.toARGB32(),
        'code': code,
      };

  factory ProjectCategory.fromJson(Map<String, dynamic> j) => ProjectCategory(
        color: Color(j['color'] as int),
        tint: Color(j['tint'] as int),
        code: j['code'] as String,
      );
}

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Pure domain entity for a study subject (e.g. "DBMS", "Algorithms").
/// No persistence concerns — Hive adapters live in /data/models.
class Subject extends Equatable {
  final String id;
  final String name;
  final int colorValue;       // ARGB int — Color.value
  final String iconKey;       // resolves to an Icon via IconCatalog
  final DateTime createdAt;
  final bool archived;

  const Subject({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.createdAt,
    this.archived = false,
  });

  Color get color => Color(colorValue);

  Subject copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    bool? archived,
  }) {
    return Subject(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      createdAt: createdAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  List<Object?> get props => [id, name, colorValue, iconKey, createdAt, archived];
}

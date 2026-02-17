import 'dart:convert';
import 'package:flutter/material.dart';

class NotificationSchedule {
  final TimeOfDay time;
  final bool goodConditionsOnly;
  final bool highTideOnly;
  final bool lowRainOnly;
  final int forecastOffset; // 0, 2, 4, 6, 8 hours
  final List<int> days; // 1 = Monday, 7 = Sunday

  NotificationSchedule({
    required this.time,
    this.goodConditionsOnly = true,
    this.highTideOnly = false,
    this.lowRainOnly = false,
    this.forecastOffset = 0,
    this.days = const [1, 2, 3, 4, 5, 6, 7],
  });

  Map<String, dynamic> toMap() {
    return {
      'hour': time.hour,
      'minute': time.minute,
      'goodConditionsOnly': goodConditionsOnly,
      'highTideOnly': highTideOnly,
      'lowRainOnly': lowRainOnly,
      'forecastOffset': forecastOffset,
      'days': days,
    };
  }

  factory NotificationSchedule.fromMap(Map<String, dynamic> map) {
    return NotificationSchedule(
      time: TimeOfDay(hour: map['hour'], minute: map['minute']),
      goodConditionsOnly: map['goodConditionsOnly'] ?? true,
      highTideOnly: map['highTideOnly'] ?? false,
      lowRainOnly: map['lowRainOnly'] ?? false,
      forecastOffset: map['forecastOffset'] ?? 0,
      days: List<int>.from(map['days'] ?? [1, 2, 3, 4, 5, 6, 7]),
    );
  }

  String toJson() => json.encode(toMap());

  factory NotificationSchedule.fromJson(String source) =>
      NotificationSchedule.fromMap(json.decode(source));

  String get timeString =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      
  NotificationSchedule copyWith({
    TimeOfDay? time,
    bool? goodConditionsOnly,
    bool? highTideOnly,
    bool? lowRainOnly,
    int? forecastOffset,
    List<int>? days,
  }) {
    return NotificationSchedule(
      time: time ?? this.time,
      goodConditionsOnly: goodConditionsOnly ?? this.goodConditionsOnly,
      highTideOnly: highTideOnly ?? this.highTideOnly,
      lowRainOnly: lowRainOnly ?? this.lowRainOnly,
      forecastOffset: forecastOffset ?? this.forecastOffset,
      days: days ?? this.days,
    );
  }
}

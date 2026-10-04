import 'package:flutter/material.dart';

/// Converts the API's normalized crop rectangle into zoom and pan controls.
///
/// At 1x there is no room to pan. Moving a position control first adds enough
/// zoom to make the movement visible, while keeping the stored rectangle valid.
class ProfileCrop {
  const ProfileCrop({this.zoom = 1, this.horizontal = .5, this.vertical = .5});

  factory ProfileCrop.fromJson(Map<String, dynamic>? json) {
    final width = ((json?['width'] as num?)?.toDouble() ?? 1).clamp(1 / 3, 1.0);
    final height = ((json?['height'] as num?)?.toDouble() ?? width).clamp(
      1 / 3,
      1.0,
    );
    final x = (json?['x'] as num?)?.toDouble() ?? 0;
    final y = (json?['y'] as num?)?.toDouble() ?? 0;
    return ProfileCrop(
      zoom: 1 / width,
      horizontal: width == 1 ? .5 : (x / (1 - width)).clamp(0.0, 1.0),
      vertical: height == 1 ? .5 : (y / (1 - height)).clamp(0.0, 1.0),
    );
  }

  final double zoom;
  final double horizontal;
  final double vertical;

  ProfileCrop withZoom(double value) =>
      ProfileCrop(zoom: value, horizontal: horizontal, vertical: vertical);

  ProfileCrop withHorizontal(double value) => ProfileCrop(
    zoom: zoom == 1 ? 1.5 : zoom,
    horizontal: value,
    vertical: vertical,
  );

  ProfileCrop withVertical(double value) => ProfileCrop(
    zoom: zoom == 1 ? 1.5 : zoom,
    horizontal: horizontal,
    vertical: value,
  );

  Map<String, double> toJson() {
    final fraction = 1 / zoom;
    return {
      'x': (1 - fraction) * horizontal,
      'y': (1 - fraction) * vertical,
      'width': fraction,
      'height': fraction,
    };
  }

  // Both BoxFit.cover and Transform.scale must anchor to the selected side,
  // not the crop rectangle's center (which only spans part of [-1, 1]).
  Alignment get alignment => Alignment(horizontal * 2 - 1, vertical * 2 - 1);
}

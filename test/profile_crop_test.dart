import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/ui/profile_card.dart';
import 'package:fourfun_cod_client/core/ui/profile_crop.dart';
import 'package:fourfun_cod_client/shared/models/profile.dart';

void main() {
  test('horizontal and vertical movement at 1x creates room to pan', () {
    const crop = ProfileCrop();

    final avatar = crop.withHorizontal(0);
    final banner = crop.withVertical(1);

    expect(avatar.zoom, 1.5);
    expect(avatar.horizontal, 0);
    expect(avatar.toJson()['x'], 0);
    expect(
      ProfileCrop.fromJson(avatar.toJson()).alignment,
      Alignment.centerLeft,
    );

    expect(banner.zoom, 1.5);
    expect(banner.vertical, 1);
    expect(
      ProfileCrop.fromJson(banner.toJson()).alignment,
      Alignment.bottomCenter,
    );
  });

  test('positions use the entire available range at higher zoom', () {
    final crop = const ProfileCrop()
        .withZoom(2)
        .withHorizontal(1)
        .withVertical(0);
    expect(crop.toJson(), {'x': .5, 'y': 0, 'width': .5, 'height': .5});
    final restored = ProfileCrop.fromJson(crop.toJson());
    expect(restored.zoom, 2);
    expect(restored.alignment, Alignment.topRight);
    expect(restored.withHorizontal(0).alignment, Alignment.topLeft);
  });

  test('zoom preserves selected pan and legacy crop rectangles', () {
    final crop = ProfileCrop.fromJson({
      'x': .125,
      'y': .375,
      'width': .5,
      'height': .5,
    });
    expect(crop.horizontal, .25);
    expect(crop.vertical, .75);
    final zoomed = crop.withZoom(3);
    expect(zoomed.horizontal, .25);
    expect(zoomed.vertical, .75);
    final alignment = ProfileCrop.fromJson(zoomed.toJson()).alignment;
    expect(alignment.x, closeTo(-.5, 1e-10));
    expect(alignment.y, closeTo(.5, 1e-10));
  });

  testWidgets('profile card applies the pan to both avatar and banner', (
    tester,
  ) async {
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScL1GQAAAABJRU5ErkJggg==',
      ),
    );
    final avatarCrop = const ProfileCrop()
        .withZoom(2)
        .withHorizontal(1)
        .toJson();
    final bannerCrop = const ProfileCrop().withZoom(2).withVertical(0).toJson();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ProfileCard(
              profile: ProfileData(
                userId: 'user',
                username: 'user',
                displayName: 'User',
                name: 'User',
                status: 'ONLINE',
                avatarCrop: avatarCrop,
                bannerCrop: bannerCrop,
              ),
              avatarBytes: png,
              bannerBytes: png,
            ),
          ),
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    final avatar = images.singleWhere((image) => image.height == 72);
    final banner = images.singleWhere((image) => image.height == 112);
    expect(avatar.alignment, Alignment.centerRight);
    expect(banner.alignment, Alignment.topCenter);
    for (final (image, alignment) in [
      (avatar, Alignment.centerRight),
      (banner, Alignment.topCenter),
    ]) {
      final transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byWidget(image),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.alignment, alignment);
      expect(transform.transform.storage[0], 2);
    }
  });
}

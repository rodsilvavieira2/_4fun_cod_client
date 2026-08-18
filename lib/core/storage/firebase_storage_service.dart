import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Serviço de object storage (abstração sobre o Firebase Storage, §6.2).
///
/// O backend nunca recebe arquivos: o client faz upload **direto** e o
/// backend só persiste a URL de download (§3.9 do plano de arquitetura).
abstract class StorageService {
  /// Faz upload do avatar e retorna a URL de download, seguindo a convenção
  /// `avatars/{uid}/{uid}-{timestamp}.{ext}`.
  Future<String> uploadAvatar({
    required String uid,
    required String filePath,
    required String contentType,
  });

  /// Remove o arquivo de avatar (`avatars/{uid}/{fileName}`).
  Future<void> deleteAvatar({required String uid, required String fileName});
}

/// Implementação via Firebase Storage — único lugar (junto de `core/storage`)
/// que importa `firebase_storage`.
class FirebaseStorageService implements StorageService {
  FirebaseStorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<String> uploadAvatar({
    required String uid,
    required String filePath,
    required String contentType,
  }) async {
    final extension = filePath.split('.').last.toLowerCase();
    final fileName = '$uid-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final reference = _storage.ref('avatars/$uid/$fileName');
    final task = await reference.putFile(
      File(filePath),
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }

  @override
  Future<void> deleteAvatar({
    required String uid,
    required String fileName,
  }) async {
    await _storage.ref('avatars/$uid/$fileName').delete();
  }
}

/// Provider do serviço de storage (Firebase Storage).
final storageServiceProvider = Provider<StorageService>(
  (ref) => FirebaseStorageService(),
);

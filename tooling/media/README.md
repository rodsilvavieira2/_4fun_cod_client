# tooling/media — benchmarks, soak e fault injection (Fase 5)

Pasta reservada pelo plano §31/`tooling/media/`. Conteúdo atual: só este
README — harnesses chegam com M5/M6 (soak 8 h voz / 2 h voz+vídeo, matriz
packet-loss, TURN, benchmark Release legacy-vs-native, A/V flash+click).

## Comandos de validação planejados (plano §33.7)

```bash
# Rust (após criar crates/scripts, adaptar aos nomes efetivos)
cargo test --manifest-path native/Cargo.toml --workspace
cargo test --manifest-path native/Cargo.toml --workspace --release
cargo clippy --manifest-path native/Cargo.toml --workspace --all-targets

# Flutter
flutter analyze
flutter test
flutter build linux --release
# Em host Windows:
flutter build windows --release
```

## Estado atual (M1)

- `cargo test -p fourfun_media_core`: 39/39 verdes.
- `cargo clippy -p fourfun_media_core --all-targets`: limpo.
- `flutter analyze` (arquivos novos): limpo.
- 15 testes Dart novos: selector (5), bridge (6), mapper (2), caminho A (2).
- Soak/packet-loss/A-V exigem harness + hardware físico: NÃO equivalem a
  build verde e ficam para M5/M6.

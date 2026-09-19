import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import 'channels_providers.dart';

/// Diálogo de criação de canal moderno tipo macOS (nome + tipo TEXT/VOICE) — apenas OWNER.
Future<void> showCreateChannelDialog(
  BuildContext context, {
  required String serverId,
}) {
  return showMacModalWindow<void>(
    context: context,
    title: 'Criar canal',
    maxWidth: 420,
    child: _CreateChannelDialog(serverId: serverId),
  );
}

class _CreateChannelDialog extends ConsumerStatefulWidget {
  const _CreateChannelDialog({required this.serverId});

  final String serverId;

  @override
  ConsumerState<_CreateChannelDialog> createState() =>
      _CreateChannelDialogState();
}

class _CreateChannelDialogState extends ConsumerState<_CreateChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  ChannelType _type = ChannelType.text;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating || !_formKey.currentState!.validate()) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ref
          .read(channelsControllerProvider(widget.serverId).notifier)
          .create(_nameController.text.trim(), _type);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _nameController,
              autofocus: true,
              label: 'NOME DO CANAL',
              hintText: 'ex: geral, novidades',
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Informe o nome do canal.'
                  : null,
              onFieldSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 18),
            const Text(
              'TIPO DE CANAL',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            AppSegmentedControl<ChannelType>(
              selectedValue: _type,
              onChanged: (type) => setState(() => _type = type),
              items: const [
                SegmentItem(
                  value: ChannelType.text,
                  label: 'Texto',
                  icon: AppIcons.channelText,
                ),
                SegmentItem(
                  value: ChannelType.voice,
                  label: 'Voz & Vídeo',
                  icon: AppIcons.volumeHigh,
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: AppTokens.accentPurple,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  onPressed: _creating
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: 'Criar canal',
                  variant: AppButtonVariant.primary,
                  loading: _creating,
                  onPressed: _creating ? null : _create,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:ai_chan/onboarding/domain/interfaces/i_chat_export_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';

/// Implementación del servicio de exportación de chat
/// Actúa como adapter entre el contexto de onboarding y chat
class ChatExportServiceAdapter implements IChatExportService {
  const ChatExportServiceAdapter(this._chatRepository);
  final IChatRepository _chatRepository;

  @override
  Future<void> saveExport(final Map<String, dynamic> exportData) async {
    await _chatRepository.saveAll(exportData);
  }

  @override
  Future<Map<String, dynamic>?> getExport() async {
    return await _chatRepository.loadAll();
  }

  @override
  Future<bool> hasExport() async {
    final data = await _chatRepository.loadAll();
    return data != null && data.isNotEmpty;
  }
}

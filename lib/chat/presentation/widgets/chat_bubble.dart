import 'package:ai_chan/shared/presentation/constants/app_colors.dart';
import 'audio_message_player_with_subs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'dart:io';
import 'package:ai_chan/shared/domain/models/index.dart';
import 'package:ai_chan/chat/application/services/message_text_processor_service.dart';
import 'package:ai_chan/shared/application/services/file_ui_service.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.message,
    required this.fileService,
    this.isLastUserMessage = false,
    this.imageDir,
    this.onRetry,
    this.onImageTap,
    this.isAudioPlaying,
    this.onToggleAudio,
    this.getAudioPosition,
    this.getAudioDuration,
    super.key,
  });
  // ===== Helpers de UI reutilizables para reducir duplicación =====
  Widget _footerRow({
    required final BuildContext context,
    required final Message message,
    required final bool isUser,
    required final Widget statusWidget,
    final bool showRetry = true,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Mantener un pequeño espacio a la izquierda dentro del row
        const SizedBox(width: 8),
        Text(
          MessageTextProcessorService.formatMessageTime(message.dateTime),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        if (isUser) ...[
          const SizedBox(width: 4),
          statusWidget,
          if (showRetry && message.status == MessageStatus.failed) ...[
            const SizedBox(width: 6),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              tooltip: 'Reintentar',
              onPressed: () => onRetry?.call(),
            ),
          ],
        ],
      ],
    );
  }

  List<Widget> _buildMarkdownBlocks(final String text) {
    if (text.trim().isEmpty) return const [];
    return MarkdownGenerator().buildWidgets(
      MessageTextProcessorService.cleanMessageText(text),
    );
  }

  Widget _callHeader({
    required final bool isUser,
    required final bool isSummary,
    required final bool isPlaceholder,
    final CallStatus? callStatus,
  }) {
    String title;
    IconData icon;
    Color color = isUser ? AppColors.primary : AppColors.secondary;
    switch (callStatus) {
      case CallStatus.placeholder:
        title = isUser ? 'Llamando...' : 'Llamada entrante';
        icon = isUser ? Icons.call_made : Icons.call_received;
        break;
      case CallStatus.active:
        title = 'Llamada en curso';
        icon = Icons.call;
        color = Colors.green;
        break;
      case CallStatus.paused:
        title = 'Llamada pausada';
        icon = Icons.pause_circle;
        color = Colors.amber;
        break;
      case CallStatus.completed:
        title = isUser ? 'Llamada realizada' : 'Llamada recibida';
        icon = isUser ? Icons.call_made : Icons.call_received;
        break;
      case CallStatus.rejected:
        title = 'Llamada rechazada';
        icon = Icons.call_end;
        color = Colors.redAccent;
        break;
      case CallStatus.missed:
        title = 'Llamada no contestada';
        icon = Icons.call_missed;
        color = Colors.orangeAccent;
        break;
      case CallStatus.failed:
        title = 'Llamada falló';
        icon = Icons.error;
        color = Colors.red;
        break;
      case CallStatus.canceled:
        title = 'Llamada cancelada';
        icon = Icons.call_end;
        color = Colors.deepOrangeAccent;
        break;
      case null:
        if (isPlaceholder) {
          title = isUser ? 'Llamando...' : 'Llamada recibida';
          icon = isUser ? Icons.call_made : Icons.call_received;
        } else {
          title = isUser ? 'Llamada realizada' : 'Llamada recibida';
          icon = isUser ? Icons.call_made : Icons.call_received;
        }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildBubbleContent({
    required final BuildContext context,
    required final Widget child,
    required final bool useIntrinsicWidth,
    required final bool isUser,
    required final Color borderColor,
    required final Color glowColor,
    final EdgeInsetsGeometry? padding,
    final bool forceFullWidth = false,
  }) {
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: glowColor.withAlpha((0.4 * 255).round()),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
    // If requested, force the bubble to occupy the available width (used for
    // images in portrait mode so they appear side-to-side).
    if (forceFullWidth) {
      try {
        final mediaWidth = MediaQuery.of(context).size.width;
        final fullWidth =
            mediaWidth - 20; // tomar en cuenta margen horizontal del container
        return SizedBox(width: fullWidth, child: bubble);
      } on Exception catch (_) {
        return bubble;
      }
    }

    // Forzar un ancho visual consistente para todos los bubbles independientemente
    // de si el mensaje es corto o largo: aplicamos un minWidth y maxWidth relativos
    // al ancho de la pantalla. Esto mantiene la apariencia uniforme.
    try {
      final mediaWidth = MediaQuery.of(context).size.width;
      final maxWidth = mediaWidth * 0.78; // 78% del ancho de pantalla
      double minWidth =
          mediaWidth * 0.32; // 32% del ancho de pantalla como mínimo
      if (minWidth < 120) {
        minWidth = 120; // no dejar demasiado pequeño en pantallas pequeñas
      }
      if (minWidth > 220) {
        minWidth =
            220; // tope razonable para burbujas pequeñas en pantallas grandes
      }

      // Si el bubble contiene elementos que ya controlan su ancho (useIntrinsicWidth)
      // respetamos el maxWidth pero seguimos aplicando minWidth para consistencia.
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
        child: bubble,
      );
    } on Exception catch (_) {
      // Si por alguna razón MediaQuery no está disponible, caer al comportamiento por defecto
      return bubble;
    }
  }

  final Message message;
  final bool isLastUserMessage;
  final Directory? imageDir;
  final FileUIService fileService;
  // Callbacks injected by the parent to avoid Provider usage inside the widget.
  // onRetry should trigger a retry of the last failed message when provided.
  final Future<void> Function()? onRetry;
  // onImageTap is called when the user taps an image; parent should show the
  // gallery/dialog because it owns the message list and deletion logic.
  final Future<void> Function()? onImageTap;
  // Audio playback callbacks injected from parent (ChatProvider)
  final bool Function(Message)? isAudioPlaying;
  final Future<void> Function(Message)? onToggleAudio;
  final Duration Function()? getAudioPosition;
  final Duration Function()? getAudioDuration;

  Widget _buildImageContent(final Message message, final Color glowColor) {
    final imageUrl = message.image?.url;
    if (imageUrl != null && imageUrl.isNotEmpty && imageDir != null) {
      final fileName = fileService.getFileName(imageUrl);
      final absPath = fileService.joinPath(imageDir!.path, fileName);

      return FutureBuilder<bool>(
        future: fileService.fileExists(absPath),
        builder: (final context, final snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 150,
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData && snapshot.data == true) {
            return _buildImageWidget(absPath, message, glowColor);
          }

          return const SizedBox.shrink();
        },
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildImageWidget(
    final String imagePath,
    final Message message,
    final Color glowColor,
  ) {
    final isUser = message.sender == MessageSender.user;
    return Builder(
      builder: (final context) {
        // Calcular ancho máximo disponible y orientación, pero respetar breakpoint
        final media = MediaQuery.of(context);
        final mediaWidth = media.size.width;
        const double desktopBreakpoint =
            768; // >= 768px tratamos como desktop/tablet
        final isPortrait = media.orientation == Orientation.portrait;
        final isSmallPortrait = isPortrait && mediaWidth < desktopBreakpoint;
        final fullWidth =
            mediaWidth - 20; // coincidencia con fullWidth usado en bubble
        final maxWidth =
            mediaWidth * 0.78; // coincide con el límite del bubble en landscape
        final targetSize = 256.0;
        // Si estamos en portrait y la pantalla es pequeña queremos que la imagen ocupe todo el ancho disponible
        final imageSize = isSmallPortrait
            ? fullWidth
            : (targetSize > maxWidth ? maxWidth : targetSize);
        final alignment = isSmallPortrait
            ? Alignment.center
            : (isUser ? Alignment.centerRight : Alignment.centerLeft);

        return Align(
          alignment: alignment,
          child: GestureDetector(
            onTap: () {
              onImageTap?.call();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<List<int>?>(
                future: fileService.readFileAsBytes(imagePath),
                builder: (final context, final snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    return Image.memory(
                      Uint8List.fromList(snapshot.data!),
                      fit: BoxFit.cover,
                      width: imageSize,
                      height: imageSize,
                    );
                  }
                  return Container(
                    width: imageSize,
                    height: imageSize,
                    color: Colors.grey[800],
                    child: const Icon(Icons.image, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(final BuildContext context) {
    final isUser = message.sender == MessageSender.user;
    final borderColor = isUser ? AppColors.primary : AppColors.secondary;
    final glowColor = isUser ? AppColors.primary : AppColors.secondary;

    Widget statusWidget = const SizedBox.shrink();
    if (isUser) {
      IconData icon;
      Color color;
      switch (message.status) {
        case MessageStatus.sending:
          icon = Icons.access_time; // esperando envío / sin red todavía
          color = Colors.grey;
          break;
        case MessageStatus.sent:
          icon = Icons.check; // enviado a la API
          color = Colors.grey;
          break;
        case MessageStatus.read:
          icon = Icons.done_all; // IA ya respondió
          color = AppColors.cyberpunkYellow;
          break;
        case MessageStatus.failed:
          icon = Icons.error_outline; // fallo de red/envío
          color = Colors.redAccent;
          break;
      }
      statusWidget = Icon(icon, size: 16, color: color);
    }

    final shouldShowText = !message.isAudio && message.text.trim().isNotEmpty;
    final hasImage =
        message.image != null &&
        message.image!.url != null &&
        message.image!.url!.isNotEmpty;
    // Mostrar player sólo cuando el mensaje está marcado como audio y ya tiene audio URL persistida.
    final hasAudio =
        message.isAudio &&
        (message.audio?.url != null && message.audio!.url!.isNotEmpty);
    // Si el mensaje está marcado como audio pero aún no tiene audio URL, no mostrar nada
    final isAwaitingAudio =
        message.isAudio &&
        (message.audio?.url == null || message.audio!.url!.isEmpty);
    if (isAwaitingAudio) return const SizedBox.shrink();
    final isVoiceCallSummary = message.isVoiceCallSummary;
    final bool isCallPlaceholder =
        message.callStatus == CallStatus.placeholder ||
        message.text.trim() == '[call][/call]';
    final callStatus = message.callStatus;

    Widget bubbleContent;
    bool useIntrinsicWidth = false;
    EdgeInsetsGeometry padding = const EdgeInsets.all(14);
    if (hasImage && hasAudio) {
      // Caso combinado: imagen + nota de voz
      final showCaption = message.text
          .trim()
          .isNotEmpty; // ignorar isAudio para caption
      final isShortCaption =
          !showCaption || (showCaption && message.text.length < 80);
      // Forzar tamaño reducido cuando hay imagen para que el bubble no ocupe ancho completo
      useIntrinsicWidth = true;
      padding = isShortCaption
          ? const EdgeInsets.all(6)
          : const EdgeInsets.all(14);
      bubbleContent = Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageContent(message, glowColor),
          const SizedBox(height: 8),
          Stack(
            children: [
              AudioMessagePlayerWithSubs(
                message: message,
                width: 200,
                isPlaying: isAudioPlaying ?? ((_) => false),
                togglePlay: onToggleAudio ?? ((_) async {}),
                getPlayingPosition: getAudioPosition,
                getPlayingDuration: getAudioDuration,
                fileService: fileService,
              ),
              if (isUser && message.status == MessageStatus.sending)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(
                              (isUser ? AppColors.primary : AppColors.secondary)
                                  .withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (showCaption) ...[
            const SizedBox(height: 8),
            ...MarkdownGenerator().buildWidgets(
              MessageTextProcessorService.cleanMessageText(message.text),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: _footerRow(
                context: context,
                message: message,
                isUser: isUser,
                statusWidget: statusWidget,
              ),
            ),
          ),
        ],
      );
    } else if (hasImage) {
      // Siempre limitar ancho del bubble si contiene una imagen
      useIntrinsicWidth = true;
      final isShortText =
          !shouldShowText || (shouldShowText && message.text.length < 80);
      padding = isShortText
          ? const EdgeInsets.all(6)
          : const EdgeInsets.all(14);
      bubbleContent = Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageContent(message, glowColor),
          if (shouldShowText) ...[
            const SizedBox(height: 8),
            ..._buildMarkdownBlocks(message.text),
          ],
          SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: _footerRow(
                context: context,
                message: message,
                isUser: isUser,
                statusWidget: statusWidget,
              ),
            ),
          ),
        ],
      );
    } else if (hasAudio) {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              // Usar reproductor con subtítulos flotantes reutilizando efecto cyberpunk
              AudioMessagePlayerWithSubs(
                message: message,
                isPlaying: isAudioPlaying ?? ((_) => false),
                togglePlay: onToggleAudio ?? ((_) async {}),
                getPlayingPosition: getAudioPosition,
                getPlayingDuration: getAudioDuration,
                fileService: fileService,
              ),
              if (isUser && message.status == MessageStatus.sending)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(
                              (isUser ? AppColors.primary : AppColors.secondary)
                                  .withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (shouldShowText) ...[
            const SizedBox(height: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...MarkdownGenerator().buildWidgets(
                    MessageTextProcessorService.cleanMessageText(message.text),
                  ),
                ],
              ),
            ),
          ],
          _footerRow(
            context: context,
            message: message,
            isUser: isUser,
            statusWidget: statusWidget,
          ),
        ],
      );
    } else if (isVoiceCallSummary) {
      // Mensaje de resumen de llamada de voz
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _callHeader(
            isUser: isUser,
            isSummary: true,
            isPlaceholder: false,
            callStatus: callStatus,
          ),
          const SizedBox(height: 6),
          // Duración
          if (message.callDuration != null)
            Text(
              'Duración: ${message.formattedCallDuration}',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
          const SizedBox(height: 8),
          // Contenido del resumen
          if (shouldShowText && message.text.isNotEmpty) ...[
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [..._buildMarkdownBlocks(message.text)],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _footerRow(
            context: context,
            message: message,
            isUser: isUser,
            statusWidget: statusWidget,
          ),
        ],
      );
    } else if (isCallPlaceholder ||
        callStatus == CallStatus.rejected ||
        callStatus == CallStatus.missed ||
        callStatus == CallStatus.canceled) {
      // Placeholder o estados de llamada sin resumen
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _callHeader(
            isUser: isUser,
            isSummary: false,
            isPlaceholder: isCallPlaceholder,
            callStatus:
                callStatus ??
                (isCallPlaceholder ? CallStatus.placeholder : null),
          ),
          const SizedBox(height: 6),
          _footerRow(
            context: context,
            message: message,
            isUser: isUser,
            statusWidget: statusWidget,
            showRetry: false,
          ),
        ],
      );
    } else {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildMarkdownBlocks(
                  message.text.isNotEmpty ? message.text : '',
                ),
              ],
            ),
          ),
          _footerRow(
            context: context,
            message: message,
            isUser: isUser,
            statusWidget: statusWidget,
          ),
        ],
      );
    }
    // Detectar orientación y tamaño para permitir que imágenes en portrait
    // ocupen ancho completo SOLO en pantallas pequeñas (móvil). En tablets/desktop
    // mantenemos el comportamiento de 'desktop'. Usamos un breakpoint razonable.
    final media = MediaQuery.of(context);
    final mediaWidth = media.size.width;
    const double desktopBreakpoint =
        768; // >= 768px tratamos como desktop/tablet
    final isPortrait = media.orientation == Orientation.portrait;
    final isSmallPortrait = isPortrait && mediaWidth < desktopBreakpoint;
    final forceFullWidth = isSmallPortrait && hasImage;

    final outerAlignment = forceFullWidth
        ? Alignment.center
        : (isUser ? Alignment.centerRight : Alignment.centerLeft);

    return Align(
      alignment: outerAlignment,
      child: _buildBubbleContent(
        context: context,
        child: bubbleContent,
        useIntrinsicWidth: useIntrinsicWidth,
        isUser: isUser,
        borderColor: borderColor,
        glowColor: glowColor,
        padding: padding,
        forceFullWidth: forceFullWidth,
      ),
    );
  }
}

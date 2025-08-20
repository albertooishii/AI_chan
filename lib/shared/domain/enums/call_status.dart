/// Estado de una llamada - Enum compartido entre contexts
enum CallStatus {
  placeholder, // Placeholder para llamadas en chat (estado inicial)
  active, // Llamada activa en progreso
  paused, // Llamada pausada temporalmente
  completed, // Llamada completada exitosamente (común a ambos)
  rejected, // Llamada rechazada por el usuario
  missed, // Llamada perdida
  failed, // Llamada falló por error técnico
  canceled, // Llamada cancelada (normalizado - sin 'l')
}

/// Extensión para CallStatus
extension CallStatusExtension on CallStatus {
  String get name {
    switch (this) {
      case CallStatus.placeholder:
        return 'placeholder';
      case CallStatus.active:
        return 'active';
      case CallStatus.paused:
        return 'paused';
      case CallStatus.completed:
        return 'completed';
      case CallStatus.rejected:
        return 'rejected';
      case CallStatus.missed:
        return 'missed';
      case CallStatus.failed:
        return 'failed';
      case CallStatus.canceled:
        return 'canceled';
    }
  }

  static CallStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'placeholder':
        return CallStatus.placeholder;
      case 'active':
        return CallStatus.active;
      case 'paused':
        return CallStatus.paused;
      case 'completed':
        return CallStatus.completed;
      case 'rejected':
        return CallStatus.rejected;
      case 'missed':
        return CallStatus.missed;
      case 'failed':
        return CallStatus.failed;
      case 'canceled':
      case 'cancelled': // Acepta ambas ortografías
        return CallStatus.canceled;
      default:
        return CallStatus.placeholder;
    }
  }

  /// Verifica si la llamada está en progreso
  bool get isInProgress =>
      this == CallStatus.active || this == CallStatus.paused;

  /// Verifica si la llamada terminó (cualquier estado final)
  bool get isFinished => !isInProgress && this != CallStatus.placeholder;

  /// Verifica si la llamada fue exitosa
  bool get isSuccessful => this == CallStatus.completed;

  /// Verifica si la llamada falló o fue problemática
  bool get isFailed =>
      this == CallStatus.failed ||
      this == CallStatus.rejected ||
      this == CallStatus.missed;
}

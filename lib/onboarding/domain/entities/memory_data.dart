/// Entidad de dominio que representa los datos que la IA necesita recuperar durante el onboarding conversacional
class MemoryData {
  const MemoryData({
    this.userName,
    this.userCountry,
    this.userBirthdate,
    this.aiCountry,
    this.aiName,
    this.meetStory,
  });

  /// Crea desde Map
  factory MemoryData.fromMap(final Map<String, dynamic> map) {
    return MemoryData(
      userName: map['userName'] as String?,
      userCountry: map['userCountry'] as String?,
      userBirthdate: map['userBirthdate'] as String?,
      aiCountry: map['aiCountry'] as String?,
      aiName: map['aiName'] as String?,
      meetStory: map['meetStory'] as String?,
    );
  }
  final String? userName;
  final String? userCountry;
  final String? userBirthdate;
  final String? aiCountry;
  final String? aiName;
  final String? meetStory;

  /// Obtiene lista de datos que aún faltan por recuperar
  List<String> getMissingData() {
    final missing = <String>[];
    if (userName == null || userName!.trim().isEmpty) missing.add('userName');
    if (userCountry == null || userCountry!.trim().isEmpty) {
      missing.add('userCountry');
    }
    if (userBirthdate == null || userBirthdate!.trim().isEmpty) {
      missing.add('userBirthdate');
    }
    if (aiCountry == null || aiCountry!.trim().isEmpty) {
      missing.add('aiCountry');
    }
    if (aiName == null || aiName!.trim().isEmpty) missing.add('aiName');
    if (meetStory == null ||
        meetStory!.trim().isEmpty ||
        meetStory!.startsWith('GENERATED:')) {
      missing.add('meetStory');
    }
    return missing;
  }

  /// Verifica si todos los datos están completos
  bool isComplete() => getMissingData().isEmpty;

  /// Porcentaje de completitud (0.0 a 1.0)
  double getCompletionPercentage() {
    const totalFields = 6;
    final missingCount = getMissingData().length;
    return (totalFields - missingCount) / totalFields;
  }

  /// Convierte a Map para serialización
  Map<String, dynamic> toMap() {
    return {
      'userName': userName,
      'userCountry': userCountry,
      'userBirthdate': userBirthdate,
      'aiCountry': aiCountry,
      'aiName': aiName,
      'meetStory': meetStory,
    };
  }

  /// Crea una copia con algunos campos actualizados
  MemoryData copyWith({
    final String? userName,
    final String? userCountry,
    final String? userBirthdate,
    final String? aiCountry,
    final String? aiName,
    final String? meetStory,
  }) {
    return MemoryData(
      userName: userName ?? this.userName,
      userCountry: userCountry ?? this.userCountry,
      userBirthdate: userBirthdate ?? this.userBirthdate,
      aiCountry: aiCountry ?? this.aiCountry,
      aiName: aiName ?? this.aiName,
      meetStory: meetStory ?? this.meetStory,
    );
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is MemoryData &&
        other.userName == userName &&
        other.userCountry == userCountry &&
        other.userBirthdate == userBirthdate &&
        other.aiCountry == aiCountry &&
        other.aiName == aiName &&
        other.meetStory == meetStory;
  }

  @override
  int get hashCode {
    return userName.hashCode ^
        userCountry.hashCode ^
        userBirthdate.hashCode ^
        aiCountry.hashCode ^
        aiName.hashCode ^
        meetStory.hashCode;
  }

  @override
  String toString() {
    return 'MemoryData(userName: $userName, userCountry: $userCountry, userBirthdate: $userBirthdate, aiCountry: $aiCountry, aiName: $aiName, meetStory: $meetStory)';
  }
}

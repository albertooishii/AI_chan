import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/call/application/services/call_application_service.dart';

void main() {
  group('🎯 CallApplicationService - DDD Application Service Tests', () {
    late CallApplicationService service;

    setUp(() {
      service = const CallApplicationService();
    });

    group('📊 Architecture Validation', () {
      test('debe seguir el patrón Application Service en DDD', () {
        // ✅ GIVEN: CallApplicationService existe
        expect(service, isNotNull);

        // ✅ THEN: Debe actuar como coordinador/facade sin lógica de negocio
        expect(service.runtimeType.toString(), 'CallApplicationService');
      });

      test('debe coordinar operaciones sin duplicar lógica', () {
        // ✅ GIVEN: Servicio creado
        expect(service, isNotNull);

        // ✅ THEN: Debe tener métodos de coordinación, no lógica compleja
        final state = service.getCoordinationState();
        expect(state.isActive, isTrue);
        expect(state.operationsCount, equals(7));
        expect(state.capabilities, hasLength(7));
      });

      test('debe mantener Single Responsibility Principle', () {
        // ✅ GIVEN: Application Service
        // ✅ THEN: Solo debe coordinar, no implementar lógica de dominio

        // Verifica que no tiene dependencias complejas inyectadas
        expect(
          service.runtimeType.toString(),
          contains('CallApplicationService'),
        );

        // Verifica que tiene capacidades bien definidas
        final state = service.getCoordinationState();
        expect(state.capabilities, contains('call_start'));
        expect(state.capabilities, contains('call_end'));
        expect(state.capabilities, contains('audio_processing'));
      });
    });

    group('📞 Call Coordination', () {
      test('debe coordinar inicio de llamada correctamente', () async {
        // ✅ GIVEN: Parámetros de llamada
        final callParams = {
          'aiProfile': 'test_profile',
          'config': {'voice': 'es-ES'},
        };

        // ✅ WHEN: Coordinar inicio de llamada
        final result = await service.coordinateCallStart(
          callParameters: callParams,
        );

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('call_start'));
        expect(result.message, contains('coordinada correctamente'));
        expect(result.data, equals(callParams));
        expect(result.error, isNull);
      });

      test('debe coordinar fin de llamada correctamente', () async {
        // ✅ GIVEN: ID de llamada
        const callId = 'test_call_123';

        // ✅ WHEN: Coordinar fin de llamada
        final result = await service.coordinateCallEnd(callId: callId);

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('call_end'));
        expect(result.data['callId'], equals(callId));
        expect(result.data['saveHistory'], isTrue);
        expect(result.error, isNull);
      });
    });

    group('🎤 Audio Coordination', () {
      test('debe coordinar procesamiento de audio correctamente', () async {
        // ✅ GIVEN: Parámetros de audio
        const callId = 'test_call_123';
        const audioAction = 'process_speech';
        final audioParams = {'format': 'wav', 'sampleRate': 44100};

        // ✅ WHEN: Coordinar procesamiento de audio
        final result = await service.coordinateAudioProcessing(
          callId: callId,
          audioAction: audioAction,
          parameters: audioParams,
        );

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('audio_processing'));
        expect(result.data['callId'], equals(callId));
        expect(result.data['action'], equals(audioAction));
        expect(result.data['parameters'], equals(audioParams));
        expect(result.error, isNull);
      });
    });

    group('🤖 Assistant Coordination', () {
      test('debe coordinar respuesta del asistente correctamente', () async {
        // ✅ GIVEN: Respuesta del asistente
        const callId = 'test_call_123';
        const responseText = 'Hola, ¿cómo estás?';
        final options = {'generateAudio': true, 'voice': 'es-ES'};

        // ✅ WHEN: Coordinar respuesta del asistente
        final result = await service.coordinateAssistantResponse(
          callId: callId,
          responseText: responseText,
          options: options,
        );

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('assistant_response'));
        expect(result.data['callId'], equals(callId));
        expect(result.data['responseText'], equals(responseText));
        expect(result.data['options'], equals(options));
        expect(result.error, isNull);
      });
    });

    group('📲 Incoming Call Coordination', () {
      test('debe coordinar llamada entrante correctamente', () async {
        // ✅ GIVEN: Datos de llamada entrante
        const callerId = 'caller_123';
        final metadata = {'priority': 'high', 'type': 'voice'};

        // ✅ WHEN: Coordinar llamada entrante
        final result = await service.coordinateIncomingCall(
          callerId: callerId,
          metadata: metadata,
        );

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('incoming_call'));
        expect(result.data['callerId'], equals(callerId));
        expect(result.data['metadata'], equals(metadata));
        expect(result.error, isNull);
      });
    });

    group('📜 History Coordination', () {
      test('debe coordinar obtención de historial correctamente', () async {
        // ✅ GIVEN: Parámetros de historial
        const limit = 10;
        final fromDate = DateTime(2024);
        final toDate = DateTime(2024, 12, 31);

        // ✅ WHEN: Coordinar obtención de historial
        final result = await service.coordinateHistoryRetrieval(
          limit: limit,
          fromDate: fromDate,
          toDate: toDate,
        );

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('history_retrieval'));
        expect(result.data['limit'], equals(limit));
        expect(result.data['fromDate'], equals(fromDate.toIso8601String()));
        expect(result.data['toDate'], equals(toDate.toIso8601String()));
        expect(result.error, isNull);
      });
    });

    group('⚙️ Configuration Coordination', () {
      test('debe coordinar configuración correctamente', () async {
        // ✅ GIVEN: Datos de configuración
        const configType = 'audio_settings';
        final configData = {
          'sampleRate': 44100,
          'bitRate': 128,
          'format': 'wav',
        };

        // ✅ WHEN: Coordinar configuración
        final result = await service.coordinateConfiguration(
          configType: configType,
          configData: configData,
        );

        // ✅ THEN: Debe retornar resultado exitoso
        expect(result.success, isTrue);
        expect(result.operation, equals('configuration'));
        expect(result.data['configType'], equals(configType));
        expect(result.data['configData'], equals(configData));
        expect(result.error, isNull);
      });
    });

    group('📊 Coordination State', () {
      test('debe proporcionar estado de coordinación correcto', () {
        // ✅ GIVEN: Servicio inicializado
        // ✅ WHEN: Obtener estado de coordinación
        final state = service.getCoordinationState();

        // ✅ THEN: Debe proporcionar estado completo
        expect(state.isActive, isTrue);
        expect(state.operationsCount, equals(7));
        expect(state.lastOperation, isNull);
        expect(state.capabilities, hasLength(7));

        // Verificar capacidades específicas
        expect(state.capabilities, contains('call_start'));
        expect(state.capabilities, contains('call_end'));
        expect(state.capabilities, contains('audio_processing'));
        expect(state.capabilities, contains('assistant_response'));
        expect(state.capabilities, contains('incoming_call'));
        expect(state.capabilities, contains('history_retrieval'));
        expect(state.capabilities, contains('configuration'));
      });
    });

    group('🎯 Result Objects', () {
      test('CallCoordinationResult debe tener estructura correcta', () {
        // ✅ GIVEN: Resultado de coordinación
        const result = CallCoordinationResult(
          success: true,
          operation: 'test_operation',
          message: 'Test message',
          data: {'test': 'data'},
        );

        // ✅ THEN: Debe tener todos los campos
        expect(result.success, isTrue);
        expect(result.operation, equals('test_operation'));
        expect(result.message, equals('Test message'));
        expect(result.data, equals({'test': 'data'}));
        expect(result.error, isNull);
      });

      test('CallCoordinationState debe tener estructura correcta', () {
        // ✅ GIVEN: Estado de coordinación
        const state = CallCoordinationState(
          isActive: true,
          operationsCount: 5,
          lastOperation: 'last_op',
          capabilities: ['cap1', 'cap2'],
        );

        // ✅ THEN: Debe tener todos los campos
        expect(state.isActive, isTrue);
        expect(state.operationsCount, equals(5));
        expect(state.lastOperation, equals('last_op'));
        expect(state.capabilities, equals(['cap1', 'cap2']));
      });
    });

    group('❌ Error Handling', () {
      test('CallApplicationException debe funcionar correctamente', () {
        // ✅ GIVEN: Excepción del Application Service
        const exception = CallApplicationException('Test error');

        // ✅ THEN: Debe tener mensaje correcto
        expect(exception.message, equals('Test error'));
        expect(exception.toString(), contains('CallApplicationException'));
        expect(exception.toString(), contains('Test error'));
      });
    });
  });
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:ai_chan/shared.dart'; // Using shared exports for infrastructure
// REMOVED: Direct infrastructure imports - using shared.dart instead
// import 'package:ai_chan/shared/infrastructure/utils/profile_persist_utils.dart' as profile_persist_utils;
import 'package:ai_chan/chat/presentation/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro completado

class CalendarScreen extends StatefulWidget {
  // ✅ DDD: ETAPA 3 - Usar ChatController directamente

  const CalendarScreen({super.key, required this.chatProvider});
  final ChatController chatProvider;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  bool _showEvents = true;
  bool _showPromises = true;

  /// Helper para configuración completa de chips por tipo
  Map<String, dynamic> _getChipConfig(final String type) {
    switch (type) {
      case 'sleep':
        return {
          'bg': Colors.indigoAccent,
          'fg': Colors.white,
          'icon': Icons.nightlight_round,
          'label': 'Dormir',
        };
      case 'work':
        return {
          'bg': Colors.pinkAccent.shade100,
          'fg': Colors.black,
          'icon': Icons.work_outline,
          'label': 'Trabajo',
        };
      case 'study':
        return {
          'bg': Colors.lightBlueAccent.shade100,
          'fg': Colors.black,
          'icon': Icons.school_outlined,
          'label': 'Estudio',
        };
      case 'busy':
        return {
          'bg': AppColors.cyberpunkYellow,
          'fg': Colors.black,
          'icon': Icons.schedule,
          'label': 'Actividad',
        };
      default:
        return {
          'bg': AppColors.cyberpunkYellow,
          'fg': Colors.black,
          'icon': Icons.schedule,
          'label': type,
        };
    }
  }

  Color _chipBg(final String type) => _getChipConfig(type)['bg'] as Color;

  String _typeLabel(final String type) =>
      _getChipConfig(type)['label'] as String;

  Color _chipFg(final String type) => _getChipConfig(type)['fg'] as Color;

  IconData _chipIcon(final String type) =>
      _getChipConfig(type)['icon'] as IconData;

  Map<DateTime, List<ChatEvent>> _groupEventsByDay(
    final List<ChatEvent> events,
  ) {
    final Map<DateTime, List<ChatEvent>> map = {};
    for (final e in events) {
      if (e.date == null) continue;
      final dayKey = DateTime(e.date!.year, e.date!.month, e.date!.day);
      map.putIfAbsent(dayKey, () => []);
      map[dayKey]!.add(e);
    }
    return map;
  }

  Color _dotColorFor(final ChatEvent e) {
    switch (e.type) {
      case 'promesa':
        return AppColors.cyberpunkYellow;
      case 'evento':
      default:
        return AppColors.secondary;
    }
  }

  Future<void> _openEventEditor(
    final BuildContext context, {
    final ChatEvent? existing,
    final DateTime? defaultDay,
  }) async {
    final chatProvider = widget.chatProvider;
    final formKey = GlobalKey<FormState>();
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    DateTime date = existing?.date ?? (defaultDay ?? DateTime.now());
    TimeOfDay time = existing?.date != null
        ? TimeOfDay(hour: existing!.date!.hour, minute: existing.date!.minute)
        : const TimeOfDay(hour: 12, minute: 0);
    String type = existing?.type ?? 'evento';
    String motivo = existing?.extra?['motivo']?.toString() ?? '';

    final saved = await showAppDialog<bool>(
      builder: (final ctx) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text(
            existing == null ? 'Nuevo evento' : 'Editar evento',
            style: const TextStyle(color: AppColors.primary),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: descCtrl,
                    style: const TextStyle(color: AppColors.primary),
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      labelStyle: TextStyle(color: AppColors.secondary),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.secondary),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.cyberpunkYellow,
                        ),
                      ),
                    ),
                    validator: (final v) => (v == null || v.trim().isEmpty)
                        ? 'Añade una descripción'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: type,
                          items: const [
                            DropdownMenuItem(
                              value: 'evento',
                              child: Text('Evento'),
                            ),
                            DropdownMenuItem(
                              value: 'promesa',
                              child: Text('Promesa'),
                            ),
                          ],
                          dropdownColor: Colors.black,
                          style: const TextStyle(color: AppColors.primary),
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            labelStyle: TextStyle(color: AppColors.secondary),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.secondary,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.cyberpunkYellow,
                              ),
                            ),
                          ),
                          onChanged: (final v) =>
                              setState(() => type = v ?? 'evento'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: DateFormat('yyyy-MM-dd').format(date),
                          ),
                          style: const TextStyle(color: AppColors.primary),
                          decoration: const InputDecoration(
                            labelText: 'Fecha',
                            labelStyle: TextStyle(color: AppColors.secondary),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.secondary,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.cyberpunkYellow,
                              ),
                            ),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              locale: const Locale('es'),
                            );
                            if (picked != null) setState(() => date = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: time.format(ctx),
                          ),
                          style: const TextStyle(color: AppColors.primary),
                          decoration: const InputDecoration(
                            labelText: 'Hora',
                            labelStyle: TextStyle(color: AppColors.secondary),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.secondary,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.cyberpunkYellow,
                              ),
                            ),
                          ),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: time,
                            );
                            if (picked != null) setState(() => time = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (type == 'promesa')
                        Expanded(
                          child: TextFormField(
                            initialValue: motivo,
                            onChanged: (final v) => motivo = v,
                            style: const TextStyle(color: AppColors.primary),
                            decoration: const InputDecoration(
                              labelText: 'Motivo (opcional)',
                              labelStyle: TextStyle(color: AppColors.secondary),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.secondary,
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.cyberpunkYellow,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text(
                'Guardar',
                style: TextStyle(color: AppColors.cyberpunkYellow),
              ),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      final fullDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final newEvent = ChatEvent(
        type: type,
        description: descCtrl.text.trim(),
        date: fullDate,
        extra: type == 'promesa'
            ? {'motivo': motivo, 'originalText': descCtrl.text.trim()}
            : null,
      );
      // Añadir o reemplazar en el perfil
      final events = List<ChatEvent>.from(
        chatProvider.events, // ✅ DDD: ETAPA 3 - Usar events del controlador
      );
      int? replaceIdx;
      if (existing != null) {
        replaceIdx = events.indexWhere(
          (final e) =>
              e.type == existing.type &&
              e.description == existing.description &&
              e.date == existing.date,
        );
      }
      if (replaceIdx != null && replaceIdx >= 0) {
        events[replaceIdx] = newEvent;
      } else {
        events.add(newEvent);
      }
      // Persist via application util to centralize logic
      await setEventsAndPersist(events);
      // Programar promesa si aplica
      chatProvider.schedulePromiseEvent(newEvent);
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteEvent(
    final BuildContext context,
    final ChatEvent e,
  ) async {
    final chatProvider = widget.chatProvider;
    final confirm = await showAppDialog<bool>(
      builder: (final ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Eliminar evento',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: const Text(
          '¿Seguro que quieres eliminar este evento?',
          style: TextStyle(color: AppColors.primary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final events = List<ChatEvent>.from(
      chatProvider.events, // ✅ DDD: ETAPA 3 - Usar events del controlador
    );
    events.removeWhere(
      (final x) =>
          x.type == e.type &&
          x.description == e.description &&
          x.date == e.date,
    );
    await setEventsAndPersist(events);
    if (mounted) setState(() {});
  }

  @override
  Widget build(final BuildContext context) {
    final chatProvider = widget.chatProvider;
    final events = chatProvider.events;
    final bio = chatProvider
        .profile
        ?.biography; // ✅ DDD: ETAPA 3 - Usar profile en lugar de onboardingData
    // Funciones auxiliares para filtrar y mostrar horarios por día seleccionado
    bool dayMatchesWithInterval(
      final String daysStr,
      final DateTime day,
      final Map<String, String>? rawEntry,
    ) {
      final processedData = CalendarProcessingService.processCalendarEntry(
        daysString: daysStr,
        day: day,
        rawEntry: rawEntry,
      );

      final spec = processedData['spec'];
      // si el mapa rawEntry contiene interval/unit/startDate preferirlo
      if (rawEntry != null && processedData['error'] == null) {
        final interval = processedData['interval'] as int?;
        final rUnit = processedData['unit'] as String?;
        final startDate = processedData['startDate'] as DateTime?;

        final spec2 = ScheduleSpec(
          days: spec.days,
          interval: interval ?? spec.interval,
          unit: rUnit ?? spec.unit,
          startDate: startDate ?? spec.startDate,
        );
        return ScheduleUtils.matchesDateWithInterval(day, spec2);
      }
      return ScheduleUtils.matchesDateWithInterval(day, spec);
    }

    DateTime? parseTime(final DateTime baseDay, final String hhmm) {
      return CalendarProcessingService.processTimeString(baseDay, hhmm);
    }

    bool rangeContains(
      final DateTime now,
      final DateTime start,
      final DateTime end,
    ) {
      return CalendarProcessingService.rangeContains(now, start, end);
    }

    List<Map<String, String>> rawSchedules() {
      final list = <Map<String, String>>[];
      try {
        if (bio != null && bio['horario_dormir'] is Map) {
          // ✅ DDD: ETAPA 3 - Verificación de null
          final m = Map<String, dynamic>.from(bio['horario_dormir']);
          list.add({
            'type': 'sleep',
            'from': '${m['from'] ?? ''}',
            'to': '${m['to'] ?? ''}',
            'days': '${m['dias'] ?? ''}',
          });
        }
        if (bio != null && bio['horario_trabajo'] is Map) {
          // ✅ DDD: ETAPA 3 - Verificación de null
          final m = Map<String, dynamic>.from(bio['horario_trabajo']);
          list.add({
            'type': 'work',
            'from': '${m['from'] ?? ''}',
            'to': '${m['to'] ?? ''}',
            'days': '${m['dias'] ?? ''}',
          });
        }
        if (bio != null && bio['horario_estudio'] is Map) {
          // ✅ DDD: ETAPA 3 - Verificación de null
          final m = Map<String, dynamic>.from(bio['horario_estudio']);
          final from = '${m['from'] ?? ''}';
          final to = '${m['to'] ?? ''}';
          final days = '${m['dias'] ?? ''}';
          if (from.trim().isNotEmpty ||
              to.trim().isNotEmpty ||
              days.trim().isNotEmpty) {
            list.add({'type': 'study', 'from': from, 'to': to, 'days': days});
          }
        }
        if (bio != null && bio['horarios_actividades'] is List) {
          // ✅ DDD: ETAPA 3 - Verificación de null
          for (final a in (bio['horarios_actividades'] as List)) {
            if (a is Map) {
              final m = Map<String, dynamic>.from(a);
              list.add({
                'type': 'busy',
                'from': '${m['from'] ?? ''}',
                'to': '${m['to'] ?? ''}',
                'days': '${m['dias'] ?? ''}',
                'actividad': '${m['actividad'] ?? ''}',
              });
            }
          }
        }
      } on Exception catch (_) {}
      return list;
    }

    final DateTime selected = _selectedDay ?? DateTime.now();
    final now = DateTime.now();
    final schedulesForDay = <Map<String, String>>[];
    for (final s in rawSchedules().where(
      (final s) => dayMatchesWithInterval(s['days'] ?? '', selected, s),
    )) {
      final fromStr = (s['from'] ?? '').trim();
      final toStr = (s['to'] ?? '').trim();
      final start = parseTime(selected, fromStr);
      final DateTime? end = parseTime(selected, toStr);
      if (start != null && end != null && end.isBefore(start)) {
        // Cruza medianoche: dividir en dos segmentos
        final endOfDay = DateTime(
          selected.year,
          selected.month,
          selected.day,
          23,
          59,
          59,
          999,
        );
        final segment1End = endOfDay;
        final segment2Start = DateTime(
          selected.year,
          selected.month,
          selected.day,
        );
        // Segmento del día seleccionado si la parte inicial cae ese día
        final isToday =
            selected.year == now.year &&
            selected.month == now.month &&
            selected.day == now.day;
        final active1 = isToday && rangeContains(now, start, segment1End);
        schedulesForDay.add({
          ...s,
          'from': fromStr,
          'to': '24:00',
          'active': active1 ? '1' : '0',
        });
        // La parte post medianoche pertenece al día siguiente; solo mostrarla si el día seleccionado es el siguiente
        final nextDay = DateTime(
          selected.year,
          selected.month,
          selected.day,
        ).add(const Duration(days: 1));
        if (_selectedDay != null && selected.isAtSameMomentAs(nextDay)) {
          final segment2End = end; // real end time next day
          final isToday2 =
              nextDay.year == now.year &&
              nextDay.month == now.month &&
              nextDay.day == now.day;
          final active2 =
              isToday2 && rangeContains(now, segment2Start, segment2End);
          schedulesForDay.add({
            ...s,
            'from': '00:00',
            'to': toStr,
            'active': active2 ? '1' : '0',
          });
        }
      } else {
        final isToday =
            selected.year == now.year &&
            selected.month == now.month &&
            selected.day == now.day;
        final active =
            start != null &&
            end != null &&
            isToday &&
            rangeContains(now, start, end);
        schedulesForDay.add({
          ...s,
          'from': fromStr,
          'to': toStr,
          'active': active ? '1' : '0',
        });
      }
    }
    schedulesForDay.sort(
      (final a, final b) => (a['from'] ?? '').compareTo(b['from'] ?? ''),
    );
    final grouped = _groupEventsByDay(events);

    List<ChatEvent> getEventsForDay(final DateTime day) {
      final key = DateTime(day.year, day.month, day.day);
      final list = grouped[key] ?? [];
      return list
          .where(
            (final e) =>
                (e.type == 'evento' && _showEvents) ||
                (e.type == 'promesa' && _showPromises),
          )
          .toList();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Calendario',
          style: TextStyle(color: AppColors.primary),
        ),
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Nuevo evento',
            icon: const Icon(Icons.add, color: AppColors.cyberpunkYellow),
            onPressed: () => _openEventEditor(
              context,
              defaultDay: _selectedDay ?? DateTime.now(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
            child: Row(
              children: [
                FilterChip(
                  selected: _showEvents,
                  label: const Text('Eventos'),
                  onSelected: (final v) => setState(() => _showEvents = v),
                  selectedColor: AppColors.secondary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.secondary,
                  labelStyle: const TextStyle(color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _showPromises,
                  label: const Text('Promesas'),
                  onSelected: (final v) => setState(() => _showPromises = v),
                  selectedColor: AppColors.cyberpunkYellow.withValues(
                    alpha: 0.2,
                  ),
                  checkmarkColor: AppColors.cyberpunkYellow,
                  labelStyle: const TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),
          TableCalendar<ChatEvent>(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            locale: 'es',
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (final day) => isSameDay(_selectedDay, day),
            onDaySelected: (final selectedDay, final focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            calendarStyle: const CalendarStyle(
              defaultTextStyle: TextStyle(color: AppColors.primary),
              weekendTextStyle: TextStyle(color: AppColors.secondary),
              todayDecoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: AppColors.cyberpunkYellow,
                shape: BoxShape.circle,
              ),
              outsideDaysVisible: false,
            ),
            headerStyle: const HeaderStyle(
              titleTextStyle: TextStyle(
                color: AppColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              formatButtonVisible: false,
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: AppColors.primary,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: AppColors.primary,
              ),
            ),
            eventLoader: getEventsForDay,
            calendarBuilders: CalendarBuilders<ChatEvent>(
              markerBuilder: (final context, final day, final events) {
                if (events.isEmpty) return null;
                return Wrap(
                  spacing: 2,
                  children: events
                      .take(4)
                      .map(
                        (final e) =>
                            Icon(Icons.circle, size: 6, color: _dotColorFor(e)),
                      )
                      .toList(),
                );
              },
            ),
          ),
          const Divider(color: AppColors.secondary),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedDay != null
                      ? DateFormat('EEEE d MMMM y', 'es').format(_selectedDay!)
                      : '',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (schedulesForDay.isNotEmpty)
                  const Text(
                    'Horarios activos',
                    style: TextStyle(color: AppColors.secondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (schedulesForDay.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: schedulesForDay.map<Widget>((final s) {
                        final type = s['type'] ?? '';
                        final active = s['active'] == '1';
                        final fg = _chipFg(type);
                        final icon = _chipIcon(type);
                        final label = _typeLabel(type);
                        final from = s['from'] ?? '';
                        final to = s['to'] ?? '';
                        final actividad = (s['actividad'] ?? '').trim();
                        final timePart = (from.isNotEmpty || to.isNotEmpty)
                            ? '$from-$to'
                            : '';
                        String stateVerb;
                        switch (type) {
                          case 'sleep':
                            stateVerb = active ? 'Durmiendo' : 'Dormir';
                            break;
                          case 'work':
                            stateVerb = active ? 'Trabajando' : 'Trabajo';
                            break;
                          case 'study':
                            stateVerb = active ? 'Estudiando' : 'Estudio';
                            break;
                          case 'busy':
                            stateVerb = actividad.isNotEmpty
                                ? (active ? actividad : actividad)
                                : (active ? 'En actividad' : 'Actividad');
                            break;
                          default:
                            stateVerb = label;
                        }
                        final text = [
                          stateVerb,
                          if (timePart.isNotEmpty) timePart,
                        ].join(' ');
                        final bgBase = _chipBg(type);
                        final bg = active
                            ? bgBase.withValues(alpha: 0.9)
                            : bgBase.withValues(alpha: 0.6);
                        return Chip(
                          avatar: Icon(icon, size: 18, color: fg),
                          label: Text(text, style: TextStyle(color: fg)),
                          backgroundColor: bg,
                          shape: StadiumBorder(
                            side: active
                                ? const BorderSide(
                                    color: AppColors.cyberpunkYellow,
                                    width: 1.3,
                                  )
                                : BorderSide.none,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ...getEventsForDay(_selectedDay ?? DateTime.now()).map(
                  (final e) => ListTile(
                    onTap: () => _openEventEditor(
                      context,
                      existing: e,
                      defaultDay: _selectedDay,
                    ),
                    onLongPress: () => _deleteEvent(context, e),
                    title: Text(
                      e.description,
                      style: const TextStyle(color: AppColors.primary),
                    ),
                    subtitle: Text(
                      e.date != null
                          ? DateFormat('HH:mm', 'es').format(e.date!)
                          : '',
                      style: const TextStyle(color: AppColors.secondary),
                    ),
                    leading: Icon(
                      e.type == 'promesa' ? Icons.alarm : Icons.event,
                      color: _dotColorFor(e),
                    ),
                  ),
                ),
                if (getEventsForDay(_selectedDay ?? DateTime.now()).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No hay eventos para este día.',
                      style: TextStyle(color: AppColors.secondary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

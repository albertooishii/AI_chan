import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/chat_provider.dart';
import '../models/event_entry.dart';
import '../constants/app_colors.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  bool _showEvents = true;
  bool _showPromises = true;

  Color _chipBg(String type) {
    switch (type) {
      case 'sleep':
        return Colors.indigoAccent; // noche
      case 'work':
        return Colors.pinkAccent.shade100; // trabajo suave
      case 'study':
        return Colors.lightBlueAccent.shade100; // estudio
      case 'busy':
        return AppColors.cyberpunkYellow; // actividades
      default:
        return AppColors.cyberpunkYellow;
    }
  }

  Color _chipFg(String type) {
    switch (type) {
      case 'sleep':
        return Colors.white;
      case 'work':
        return Colors.black;
      case 'study':
        return Colors.black;
      case 'busy':
        return Colors.black;
      default:
        return Colors.black;
    }
  }

  IconData _chipIcon(String type) {
    switch (type) {
      case 'sleep':
        return Icons.nightlight_round;
      case 'work':
        return Icons.work_outline;
      case 'study':
        return Icons.school_outlined;
      case 'busy':
        return Icons.schedule;
      default:
        return Icons.schedule;
    }
  }

  Map<DateTime, List<EventEntry>> _groupEventsByDay(List<EventEntry> events) {
    final Map<DateTime, List<EventEntry>> map = {};
    for (final e in events) {
      if (e.date == null) continue;
      final dayKey = DateTime(e.date!.year, e.date!.month, e.date!.day);
      map.putIfAbsent(dayKey, () => []);
      map[dayKey]!.add(e);
    }
    return map;
  }

  Color _dotColorFor(EventEntry e) {
    switch (e.type) {
      case 'promesa':
        return AppColors.cyberpunkYellow;
      case 'evento':
      default:
        return AppColors.secondary;
    }
  }

  Future<void> _openEventEditor(BuildContext context, {EventEntry? existing, DateTime? defaultDay}) async {
    final chatProvider = context.read<ChatProvider>();
    final formKey = GlobalKey<FormState>();
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    DateTime date = existing?.date ?? (defaultDay ?? DateTime.now());
    TimeOfDay time = existing?.date != null
        ? TimeOfDay(hour: existing!.date!.hour, minute: existing.date!.minute)
        : const TimeOfDay(hour: 12, minute: 0);
    String type = existing?.type ?? 'evento';
    String motivo = existing?.extra?['motivo']?.toString() ?? '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
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
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.secondary)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.cyberpunkYellow)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Añade una descripción' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: type,
                          items: const [
                            DropdownMenuItem(value: 'evento', child: Text('Evento')),
                            DropdownMenuItem(value: 'promesa', child: Text('Promesa')),
                          ],
                          dropdownColor: Colors.black,
                          style: const TextStyle(color: AppColors.primary),
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            labelStyle: TextStyle(color: AppColors.secondary),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.secondary)),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.cyberpunkYellow),
                            ),
                          ),
                          onChanged: (v) => setState(() => type = v ?? 'evento'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(text: DateFormat('yyyy-MM-dd').format(date)),
                          style: const TextStyle(color: AppColors.primary),
                          decoration: const InputDecoration(
                            labelText: 'Fecha',
                            labelStyle: TextStyle(color: AppColors.secondary),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.secondary)),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.cyberpunkYellow),
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
                          controller: TextEditingController(text: time.format(ctx)),
                          style: const TextStyle(color: AppColors.primary),
                          decoration: const InputDecoration(
                            labelText: 'Hora',
                            labelStyle: TextStyle(color: AppColors.secondary),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.secondary)),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.cyberpunkYellow),
                            ),
                          ),
                          onTap: () async {
                            final picked = await showTimePicker(context: ctx, initialTime: time);
                            if (picked != null) setState(() => time = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (type == 'promesa')
                        Expanded(
                          child: TextFormField(
                            initialValue: motivo,
                            onChanged: (v) => motivo = v,
                            style: const TextStyle(color: AppColors.primary),
                            decoration: const InputDecoration(
                              labelText: 'Motivo (opcional)',
                              labelStyle: TextStyle(color: AppColors.secondary),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.secondary)),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: AppColors.cyberpunkYellow),
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
              child: const Text('Cancelar', style: TextStyle(color: AppColors.primary)),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Guardar', style: TextStyle(color: AppColors.cyberpunkYellow)),
            ),
          ],
        );
      },
    );

    if (saved == true) {
      final fullDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      final newEvent = EventEntry(
        type: type,
        description: descCtrl.text.trim(),
        date: fullDate,
        extra: type == 'promesa' ? {'motivo': motivo, 'originalText': descCtrl.text.trim()} : null,
      );
      // Añadir o reemplazar en el perfil
      final events = List<EventEntry>.from(chatProvider.onboardingData.events ?? []);
      int? replaceIdx;
      if (existing != null) {
        replaceIdx = events.indexWhere(
          (e) => e.type == existing.type && e.description == existing.description && e.date == existing.date,
        );
      }
      if (replaceIdx != null && replaceIdx >= 0) {
        events[replaceIdx] = newEvent;
      } else {
        events.add(newEvent);
      }
      final updated = chatProvider.onboardingData.copyWith(events: events);
      chatProvider.onboardingData = updated;
      await chatProvider.saveAll();
      // Programar promesa si aplica
      chatProvider.schedulePromiseEvent(newEvent);
      if (mounted) setState(() {});
    }
  }

  void _deleteEvent(BuildContext context, EventEntry e) async {
    final chatProvider = context.read<ChatProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Eliminar evento', style: TextStyle(color: Colors.redAccent)),
        content: const Text('¿Seguro que quieres eliminar este evento?', style: TextStyle(color: AppColors.primary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final events = List<EventEntry>.from(chatProvider.onboardingData.events ?? []);
    events.removeWhere((x) => x.type == e.type && x.description == e.description && x.date == e.date);
    chatProvider.onboardingData = chatProvider.onboardingData.copyWith(events: events);
    await chatProvider.saveAll();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final events = chatProvider.events;
    final bio = chatProvider.onboardingData.biography;
    List<Map<String, String>> chips = [];
    try {
      if (bio['horario_dormir'] is Map) {
        final m = Map<String, dynamic>.from(bio['horario_dormir']);
        chips.add({
          'type': 'sleep',
          'from': (m['from'] ?? '').toString(),
          'to': (m['to'] ?? '').toString(),
          'days': (m['dias'] ?? '').toString(),
        });
      }
      if (bio['horario_trabajo'] is Map) {
        final m = Map<String, dynamic>.from(bio['horario_trabajo']);
        chips.add({
          'type': 'work',
          'from': (m['from'] ?? '').toString(),
          'to': (m['to'] ?? '').toString(),
          'days': (m['dias'] ?? '').toString(),
        });
      }
      if (bio['horario_estudio'] is Map) {
        final m = Map<String, dynamic>.from(bio['horario_estudio']);
        chips.add({
          'type': 'study',
          'from': (m['from'] ?? '').toString(),
          'to': (m['to'] ?? '').toString(),
          'days': (m['dias'] ?? '').toString(),
        });
      }
      if (bio['horarios_actividades'] is List) {
        for (final a in (bio['horarios_actividades'] as List)) {
          if (a is Map) {
            final m = Map<String, dynamic>.from(a);
            chips.add({
              'type': 'busy',
              'from': (m['from'] ?? '').toString(),
              'to': (m['to'] ?? '').toString(),
              'days': (m['dias'] ?? '').toString(),
            });
          }
        }
      }
    } catch (_) {}
    final grouped = _groupEventsByDay(events);

    List<EventEntry> getEventsForDay(DateTime day) {
      final key = DateTime(day.year, day.month, day.day);
      final list = grouped[key] ?? [];
      return list.where((e) => (e.type == 'evento' && _showEvents) || (e.type == 'promesa' && _showPromises)).toList();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Calendario', style: TextStyle(color: AppColors.primary)),
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Nuevo evento',
            icon: const Icon(Icons.add, color: AppColors.cyberpunkYellow),
            onPressed: () => _openEventEditor(context, defaultDay: _selectedDay ?? DateTime.now()),
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
                  onSelected: (v) => setState(() => _showEvents = v),
                  selectedColor: AppColors.secondary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.secondary,
                  labelStyle: const TextStyle(color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _showPromises,
                  label: const Text('Promesas'),
                  onSelected: (v) => setState(() => _showPromises = v),
                  selectedColor: AppColors.cyberpunkYellow.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.cyberpunkYellow,
                  labelStyle: const TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),
          TableCalendar<EventEntry>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            locale: 'es',
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            calendarStyle: const CalendarStyle(
              defaultTextStyle: TextStyle(color: AppColors.primary),
              weekendTextStyle: TextStyle(color: AppColors.secondary),
              todayDecoration: BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: AppColors.cyberpunkYellow, shape: BoxShape.circle),
              outsideDaysVisible: false,
              markersAutoAligned: true,
            ),
            headerStyle: const HeaderStyle(
              titleTextStyle: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
              formatButtonVisible: false,
              leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.primary),
              rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.primary),
            ),
            eventLoader: getEventsForDay,
            calendarBuilders: CalendarBuilders<EventEntry>(
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return null;
                return Wrap(
                  spacing: 2,
                  children: events.take(4).map((e) => Icon(Icons.circle, size: 6, color: _dotColorFor(e))).toList(),
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
                  _selectedDay != null ? DateFormat('EEEE d MMMM y', 'es').format(_selectedDay!) : '',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
                if (chips.isNotEmpty)
                  const Text('Horarios activos', style: TextStyle(color: AppColors.secondary, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (chips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: chips.map<Widget>((s) {
                        final type = s['type'] ?? '';
                        final bg = _chipBg(type);
                        final fg = _chipFg(type);
                        final icon = _chipIcon(type);
                        return Chip(
                          avatar: Icon(icon, size: 18, color: fg),
                          label: Text(
                            '${s['type'] ?? ''}: ${s['days'] ?? ''} ${s['from'] ?? ''}-${s['to'] ?? ''}',
                            style: TextStyle(color: fg),
                          ),
                          backgroundColor: bg,
                        );
                      }).toList(),
                    ),
                  ),
                ...getEventsForDay(_selectedDay ?? DateTime.now()).map(
                  (e) => ListTile(
                    onTap: () => _openEventEditor(context, existing: e, defaultDay: _selectedDay),
                    onLongPress: () => _deleteEvent(context, e),
                    title: Text(e.description, style: const TextStyle(color: AppColors.primary)),
                    subtitle: Text(
                      e.date != null ? DateFormat('HH:mm', 'es').format(e.date!) : '',
                      style: const TextStyle(color: AppColors.secondary),
                    ),
                    leading: Icon(e.type == 'promesa' ? Icons.alarm : Icons.event, color: _dotColorFor(e)),
                  ),
                ),
                if (getEventsForDay(_selectedDay ?? DateTime.now()).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No hay eventos para este día.', style: TextStyle(color: AppColors.secondary)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

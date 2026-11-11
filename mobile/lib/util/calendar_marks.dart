import '../state/habit_controller.dart';
import '../state/reminder_controller.dart';
import '../state/task_controller.dart';
import 'format.dart';

/// Lo que hay un día: cuántas tareas vencen (sin finalizar), cuántos recordatorios (sin hacer) y cuántos hábitos tocan.
class DayMarks {
  const DayMarks({this.tasks = 0, this.reminders = 0, this.habits = 0});

  final int tasks;
  final int reminders;
  final int habits;

  bool get isEmpty => tasks == 0 && reminders == 0 && habits == 0;

  @override
  bool operator ==(Object other) => other is DayMarks && other.tasks == tasks && other.reminders == reminders && other.habits == habits;

  @override
  int get hashCode => Object.hash(tasks, reminders, habits);

  @override
  String toString() => 'DayMarks(tareas: $tasks, recordatorios: $reminders, hábitos: $habits)';
}

/// Lo que hay el día [day] (cualquier hora de ese día, en la hora local) con los controladores que haya.
DayMarks marksFor(DateTime day, {TaskController? tasks, ReminderController? reminders, HabitController? habits}) {
  final dueTasks = tasks == null
      ? 0
      : tasks.roots(active: true).where((t) => t.due != null && sameDay(t.due!, day)).length;
  final pending = reminders == null ? 0 : reminders.items.where((r) => !r.done && sameDay(r.at, day)).length;
  final dueHabits = habits == null ? 0 : habits.habitsFor(day).length;
  return DayMarks(tasks: dueTasks, reminders: pending, habits: dueHabits);
}

/// Lo que hay cada día de un mes (el de [month]), del 1 al último.
Map<int, DayMarks> monthMarks(DateTime month, {TaskController? tasks, ReminderController? reminders, HabitController? habits}) {
  final last = DateTime(month.year, month.month + 1, 0).day;
  return {
    for (var d = 1; d <= last; d++) d: marksFor(DateTime(month.year, month.month, d), tasks: tasks, reminders: reminders, habits: habits),
  };
}

/// El resumen de un día para la consola: «3 tareas · 2 hábitos · 1 recordatorio», solo con lo que se puede tener. Sin nada, «sin pendientes».
String marksSummary(DayMarks marks, {bool withTasks = true, bool withHabits = true, bool withReminders = true}) {
  String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  final parts = [
    if (withTasks && marks.tasks > 0) count(marks.tasks, 'tarea', 'tareas'),
    if (withHabits && marks.habits > 0) count(marks.habits, 'hábito', 'hábitos'),
    if (withReminders && marks.reminders > 0) count(marks.reminders, 'recordatorio', 'recordatorios'),
  ];
  return parts.isEmpty ? 'sin pendientes' : parts.join(' · ');
}

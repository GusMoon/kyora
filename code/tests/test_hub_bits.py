from datetime import date

from kyora.core.calendar_grid import long_date, month_grid, shift_month, week_days
from kyora.system.bluetooth import device_rows
from kyora.system.stats import History


def test_month_grid_starts_on_monday_and_covers_the_month():
    grid = month_grid(2026, 10)  # 1 de octubre de 2026 es jueves
    assert len(grid) == 6 and all(len(week) == 7 for week in grid)
    assert grid[0][0] == date(2026, 9, 28) and grid[0][3] == date(2026, 10, 1)
    assert all(day.weekday() == 0 for day in (week[0] for week in grid))
    february = [d for week in month_grid(2028, 2) for d in week if d.month == 2]
    assert len(february) == 29  # bisiesto


def test_month_starting_on_sunday_and_shift():
    grid = month_grid(2026, 3)  # 1 de marzo de 2026 es domingo
    assert grid[0][6] == date(2026, 3, 1)
    assert shift_month(2026, 12, 1) == (2027, 1) and shift_month(2026, 1, -1) == (2025, 12)
    assert long_date(date(2026, 10, 21)) == "miércoles, 21 de octubre de 2026"


def test_bluetooth_devices_are_merged_and_connected_first():
    rows = device_rows([
        {"name": "S36", "connected": False, "kind": "classic"},
        {"name": "MISIK MS227", "connected": False, "kind": "classic"},
        {"name": "MISIK MS227", "connected": True, "kind": "le"},
        {"name": " ", "connected": True},
    ])
    assert [(r["name"], r["connected"]) for r in rows] == [("MISIK MS227", True), ("S36", False)]


def test_history_keeps_the_last_values():
    h = History(size=3)
    for cpu in (10, 20, 30, 40):
        h.add({"cpu": cpu, "ram": cpu + 1})
    h.add({"disk": 5})  # sin CPU no se guarda nada
    assert h.as_dict() == {"cpu": [20, 30, 40], "ram": [21, 31, 41]}


def test_dock_span_centers_clamps_and_snaps_to_the_corner():
    from kyora.ui.dock import dock_span

    assert dock_span(400, 200, 8, 856, 22) == (300, 500, False)  # centrada en el icono
    assert dock_span(50, 200, 8, 856, 22) == (30, 230, False)  # arriba no se sale del hueco
    assert dock_span(800, 300, 8, 856, 22) == (556, 856, True)  # abajo se apoya en el marco


def test_week_strip_has_today_in_the_middle():
    days = week_days(date(2026, 10, 21))
    assert [d.day for d in days] == [18, 19, 20, 21, 22, 23, 24]
    assert days[3] == date(2026, 10, 21)

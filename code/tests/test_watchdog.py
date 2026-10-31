import logging

from kyora.ui.app import SIGNAL_POLL_MS, watchdog


def test_watchdog_logs_ui_stalls_once_in_a_while(caplog):
    now = {"t": 0.0}
    beat = watchdog(lambda: now["t"], log_every=10)
    with caplog.at_level(logging.INFO, logger="kyora.ui"):
        for step in (SIGNAL_POLL_MS, SIGNAL_POLL_MS + 40):  # a tiempo (o casi): nada
            now["t"] += step / 1000
            beat()
        assert not caplog.records
        now["t"] += (SIGNAL_POLL_MS + 900) / 1000  # 900 ms tarde
        beat()
        now["t"] += (SIGNAL_POLL_MS + 400) / 1000
        beat()
        assert len(caplog.records) == 1 and "la peor, 900 ms" in caplog.records[0].getMessage()
        now["t"] += (SIGNAL_POLL_MS + 500) / 1000
        beat()  # hace menos de 10 s del aviso: se acumula
        assert len(caplog.records) == 1

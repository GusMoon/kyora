"""Bluetooth con las APIs de Windows (WinRT, paquetes oficiales de pywinrt): encender o apagar la radio y ver los
dispositivos emparejados y si están conectados. Emparejar dispositivos nuevos queda fuera (lo hace Windows).

Las llamadas de WinRT son asíncronas: aquí se esperan con asyncio.run, así que hay que usarlo desde un hilo propio.
"""
import asyncio
import logging

log = logging.getLogger("kyora.bluetooth")


def device_rows(devices):
    """Junta los dispositivos (clásicos y LE pueden repetirse con el mismo nombre) y ordena: conectados primero."""
    merged = {}
    for d in devices:
        name = (d.get("name") or "").strip()
        if not name:
            continue
        old = merged.setdefault(name, {"name": name, "connected": False, "kind": d.get("kind", "")})
        old["connected"] |= bool(d.get("connected"))
    return sorted(merged.values(), key=lambda d: (not d["connected"], d["name"].lower()))


async def _radio():
    from winrt.windows.devices.radios import Radio, RadioKind

    for radio in await Radio.get_radios_async():
        if radio.kind == RadioKind.BLUETOOTH:
            return radio
    return None


async def _devices():
    from winrt.windows.devices.bluetooth import (
        BluetoothConnectionStatus,
        BluetoothDevice,
        BluetoothLEDevice,
    )
    from winrt.windows.devices.enumeration import DeviceInformation

    found = []
    for kind, cls in (("classic", BluetoothDevice), ("le", BluetoothLEDevice)):
        for info in await DeviceInformation.find_all_async_aqs_filter(cls.get_device_selector_from_pairing_state(True)):
            try:
                device = await cls.from_id_async(info.id)
            except OSError:
                device = None
            connected = bool(device and device.connection_status == BluetoothConnectionStatus.CONNECTED)
            found.append({"name": (device.name if device else "") or info.name, "connected": connected, "kind": kind})
            if device:
                device.close()
    return found


async def _status():
    radio = await _radio()
    if radio is None:
        return {"available": False, "on": False, "devices": []}
    from winrt.windows.devices.radios import RadioState

    on = radio.state == RadioState.ON
    return {"available": True, "on": on, "devices": device_rows(await _devices()) if on else []}


async def _set(on):
    from winrt.windows.devices.radios import Radio, RadioAccessStatus, RadioState

    if await Radio.request_access_async() != RadioAccessStatus.ALLOWED:
        raise OSError("Windows no deja a Kyora cambiar el Bluetooth")
    radio = await _radio()
    if radio is None:
        raise OSError("Este equipo no tiene Bluetooth")
    result = await radio.set_state_async(RadioState.ON if on else RadioState.OFF)
    if result != RadioAccessStatus.ALLOWED:
        raise OSError("Windows no dejó cambiar el Bluetooth")


def status():
    """{available, on, devices: [{name, connected, kind}]}."""
    return asyncio.run(_status())


def set_radio(on):
    asyncio.run(_set(on))
    return status()

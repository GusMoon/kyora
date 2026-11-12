"""Wifi con la API Native Wifi de Windows (wlanapi.dll) por ctypes: estado, redes, conectar y desconectar.

No depende del idioma de Windows (netsh escribe en el de la consola). En Windows 11 24H2 la lista de redes necesita
que las apps de escritorio puedan usar la ubicación: si Windows la deniega, se lanza `LocationDenied`.
"""
import ctypes
import time
from ctypes import wintypes
from xml.sax.saxutils import escape

from kyora.system.audio import GUID

wlanapi = ctypes.WinDLL("wlanapi")

ERROR_SUCCESS = 0
ERROR_ACCESS_DENIED = 5
CONNECTED_STATE = 1  # wlan_interface_state_connected
CURRENT_CONNECTION = 7  # wlan_intf_opcode_current_connection
FLAG_CONNECTED, FLAG_HAS_PROFILE = 0x1, 0x2
CONNECT_TIMEOUT = 15
SCAN_WAIT = 3

# algoritmo de autenticación de Windows -> (authentication, encryption) del perfil; las de empresa no se admiten
AUTH = {1: ("open", "none"), 4: ("WPAPSK", "TKIP"), 7: ("WPA2PSK", "AES"), 9: ("WPA3SAE", "AES"), 10: ("OWE", "AES")}
CIPHERS = {0: "none", 2: "TKIP", 4: "AES"}


class LocationDenied(PermissionError):
    """Windows no deja ver las redes: hay que permitir la ubicación a las apps de escritorio."""


class DOT11_SSID(ctypes.Structure):
    _fields_ = [("length", wintypes.ULONG), ("ssid", ctypes.c_ubyte * 32)]

    def text(self):
        return bytes(self.ssid[: self.length]).decode("utf-8", errors="replace")


class WLAN_INTERFACE_INFO(ctypes.Structure):
    _fields_ = [("guid", GUID), ("description", wintypes.WCHAR * 256), ("state", ctypes.c_int)]


class WLAN_INTERFACE_INFO_LIST(ctypes.Structure):
    _fields_ = [("count", wintypes.DWORD), ("index", wintypes.DWORD), ("items", WLAN_INTERFACE_INFO * 1)]


class WLAN_AVAILABLE_NETWORK(ctypes.Structure):
    _fields_ = [
        ("profile", wintypes.WCHAR * 256), ("ssid", DOT11_SSID), ("bss_type", ctypes.c_int),
        ("bssids", wintypes.ULONG), ("connectable", wintypes.BOOL), ("not_connectable_reason", wintypes.DWORD),
        ("phy_count", wintypes.ULONG), ("phy_types", ctypes.c_int * 8), ("more_phy", wintypes.BOOL),
        ("signal", wintypes.ULONG), ("secured", wintypes.BOOL), ("auth", ctypes.c_int), ("cipher", ctypes.c_int),
        ("flags", wintypes.DWORD), ("reserved", wintypes.DWORD),
    ]


class WLAN_AVAILABLE_NETWORK_LIST(ctypes.Structure):
    _fields_ = [("count", wintypes.DWORD), ("index", wintypes.DWORD), ("items", WLAN_AVAILABLE_NETWORK * 1)]


class WLAN_ASSOCIATION_ATTRIBUTES(ctypes.Structure):
    _fields_ = [
        ("ssid", DOT11_SSID), ("bss_type", ctypes.c_int), ("bssid", ctypes.c_ubyte * 6), ("phy_type", ctypes.c_int),
        ("phy_index", wintypes.ULONG), ("signal", wintypes.ULONG), ("rx_rate", wintypes.ULONG), ("tx_rate", wintypes.ULONG),
    ]


class WLAN_CONNECTION_ATTRIBUTES(ctypes.Structure):
    _fields_ = [
        ("state", ctypes.c_int), ("mode", ctypes.c_int), ("profile", wintypes.WCHAR * 256),
        ("association", WLAN_ASSOCIATION_ATTRIBUTES),
        # WLAN_SECURITY_ATTRIBUTES (no se usa: basta con saber que existe para no leer de más)
        ("security_enabled", wintypes.BOOL), ("onex", wintypes.BOOL), ("auth", ctypes.c_int), ("cipher", ctypes.c_int),
    ]


class WLAN_CONNECTION_PARAMETERS(ctypes.Structure):
    _fields_ = [
        ("mode", ctypes.c_int), ("profile", wintypes.LPCWSTR), ("ssid", ctypes.c_void_p),
        ("bssid_list", ctypes.c_void_p), ("bss_type", ctypes.c_int), ("flags", wintypes.DWORD),
    ]


def _check(code, what):
    if code == ERROR_ACCESS_DENIED:
        raise LocationDenied(f"Windows no deja {what}")
    if code != ERROR_SUCCESS:
        raise OSError(f"No se pudo {what} (error {code})")


class _Client:
    """`with _Client() as (handle, guid):` abre la API y da la primera tarjeta wifi (o lanza OSError si no hay)."""

    def __enter__(self):
        self.handle = wintypes.HANDLE()
        version = wintypes.DWORD()
        _check(wlanapi.WlanOpenHandle(2, None, ctypes.byref(version), ctypes.byref(self.handle)), "abrir el wifi")
        interfaces = ctypes.POINTER(WLAN_INTERFACE_INFO_LIST)()
        _check(wlanapi.WlanEnumInterfaces(self.handle, None, ctypes.byref(interfaces)), "ver las tarjetas wifi")
        try:
            if interfaces.contents.count == 0:
                raise OSError("Este equipo no tiene wifi")
            self.guid = GUID()
            ctypes.memmove(ctypes.byref(self.guid), ctypes.byref(interfaces.contents.items[0].guid), ctypes.sizeof(GUID))
        finally:
            wlanapi.WlanFreeMemory(interfaces)
        return self.handle, self.guid

    def __exit__(self, *_):
        wlanapi.WlanCloseHandle(self.handle, None)


def _connection(handle, guid):
    """(ssid, señal) de la conexión actual, o None."""
    size, data = wintypes.DWORD(), ctypes.c_void_p()
    code = wlanapi.WlanQueryInterface(handle, ctypes.byref(guid), CURRENT_CONNECTION, None,
                                      ctypes.byref(size), ctypes.byref(data), None)
    if code != ERROR_SUCCESS:
        return None  # sin conexión, Windows responde con un error
    try:
        attrs = ctypes.cast(data, ctypes.POINTER(WLAN_CONNECTION_ATTRIBUTES)).contents
        if attrs.state != CONNECTED_STATE:
            return None
        return attrs.association.ssid.text(), int(attrs.association.signal)
    finally:
        wlanapi.WlanFreeMemory(data)


def status():
    """{available, connected, ssid, signal}, como `wifi.parse`."""
    try:
        with _Client() as (handle, guid):
            current = _connection(handle, guid)
    except OSError:
        return {"available": False, "connected": False, "ssid": "", "signal": 0}
    if current is None:
        return {"available": True, "connected": False, "ssid": "", "signal": 0}
    return {"available": True, "connected": True, "ssid": current[0], "signal": current[1]}


def scan():
    """Pide a la tarjeta que busque redes y espera un momento a que termine."""
    with _Client() as (handle, guid):
        _check(wlanapi.WlanScan(handle, ctypes.byref(guid), None, None, None), "buscar redes")
    time.sleep(SCAN_WAIT)


def merge_networks(raw):
    """Junta las entradas de una misma red (Windows repite la que tiene perfil) y ordena: conectada, luego señal."""
    merged = {}
    for n in raw:
        if not n["ssid"]:
            continue  # redes ocultas: sin nombre no se pueden elegir
        old = merged.get(n["ssid"])
        if old is None:
            merged[n["ssid"]] = dict(n)
            continue
        old["signal"] = max(old["signal"], n["signal"])
        old["connected"] |= n["connected"]
        if n["has_profile"] and not old["has_profile"]:
            old["has_profile"], old["profile"] = True, n["profile"]
    return sorted(merged.values(), key=lambda n: (not n["connected"], -n["signal"], n["ssid"].lower()))


def networks():
    """Redes que se ven: [{ssid, signal, secured, auth, cipher, has_profile, profile, connected, supported}]."""
    with _Client() as (handle, guid):
        data = ctypes.POINTER(WLAN_AVAILABLE_NETWORK_LIST)()
        _check(wlanapi.WlanGetAvailableNetworkList(handle, ctypes.byref(guid), 0, None, ctypes.byref(data)),
               "ver las redes (¿ubicación desactivada?)")
        try:
            count = data.contents.count
            items = ctypes.cast(ctypes.byref(data.contents.items), ctypes.POINTER(WLAN_AVAILABLE_NETWORK * count)).contents
            raw = [{
                "ssid": n.ssid.text(), "signal": int(n.signal), "secured": bool(n.secured),
                "auth": n.auth, "cipher": n.cipher, "has_profile": bool(n.flags & FLAG_HAS_PROFILE),
                "profile": n.profile, "connected": bool(n.flags & FLAG_CONNECTED), "supported": n.auth in AUTH,
            } for n in items]
        finally:
            wlanapi.WlanFreeMemory(data)
    return merge_networks(raw)


def profile_xml(ssid, auth, cipher, password=None):
    """Perfil de Windows para una red personal (abierta, WPA-PSK, WPA2-PSK, WPA3-SAE u OWE)."""
    if auth not in AUTH:
        raise ValueError("Kyora solo sabe conectarse a redes personales (no a redes de empresa con usuario)")
    authentication, encryption = AUTH[auth]
    encryption = CIPHERS.get(cipher, encryption) if authentication != "open" else "none"
    if authentication in ("WPA2PSK", "WPA3SAE", "OWE") and encryption == "TKIP" and cipher != 2:
        encryption = "AES"
    key = ""
    if authentication in ("WPAPSK", "WPA2PSK", "WPA3SAE"):
        if not password:
            raise ValueError("Esta red necesita contraseña")
        key = (
            "<sharedKey><keyType>passPhrase</keyType><protected>false</protected>"
            f"<keyMaterial>{escape(password)}</keyMaterial></sharedKey>"
        )
    raw = ssid.encode("utf-8")
    return (
        '<?xml version="1.0"?>'
        '<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">'
        f"<name>{escape(ssid)}</name>"
        f"<SSIDConfig><SSID><hex>{raw.hex().upper()}</hex><name>{escape(ssid)}</name></SSID></SSIDConfig>"
        "<connectionType>ESS</connectionType><connectionMode>auto</connectionMode>"
        f"<MSM><security><authEncryption><authentication>{authentication}</authentication>"
        f"<encryption>{encryption}</encryption><useOneX>false</useOneX></authEncryption>{key}</security></MSM>"
        "</WLANProfile>"
    )


def connect(ssid, password=None):
    """Conecta a `ssid` (con su perfil guardado, o creando uno con `password`). Devuelve el estado al terminar.

    Lanza ValueError si falta la contraseña o la red no es compatible y OSError si no conecta a tiempo.
    """
    target = next((n for n in networks() if n["ssid"] == ssid), None)
    if target is None:
        raise OSError(f"La red {ssid} ya no se ve")
    created = False
    with _Client() as (handle, guid):
        profile = target["profile"] if target["has_profile"] and not password else ssid
        if password or not target["has_profile"]:
            xml = profile_xml(ssid, target["auth"], target["cipher"], password)
            reason = wintypes.DWORD()
            _check(wlanapi.WlanSetProfile(handle, ctypes.byref(guid), 0, xml, None, True, None, ctypes.byref(reason)),
                   "guardar la red")
            created = True
        params = WLAN_CONNECTION_PARAMETERS(0, profile, None, None, 1, 0)
        _check(wlanapi.WlanConnect(handle, ctypes.byref(guid), ctypes.byref(params), None), "conectar")
        deadline = time.monotonic() + CONNECT_TIMEOUT
        while time.monotonic() < deadline:
            time.sleep(0.5)
            current = _connection(handle, guid)
            if current and current[0] == ssid:
                return status()
        if created:
            wlanapi.WlanDeleteProfile(handle, ctypes.byref(guid), profile, None)  # no guardar una contraseña mala
    raise OSError("Contraseña incorrecta o la red no responde")


def disconnect():
    with _Client() as (handle, guid):
        _check(wlanapi.WlanDisconnect(handle, ctypes.byref(guid), None), "desconectar")

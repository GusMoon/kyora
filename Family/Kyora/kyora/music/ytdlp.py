"""Lo que Música necesita de yt-dlp, sin Qt ni red: las opciones, la lectura de sus respuestas, los errores en español
y dónde está FFmpeg."""
import glob
import os
import re
import shutil

PLAYLISTS_URL = "https://www.youtube.com/feed/playlists"
LIKED = {"id": "LL", "title": "Videos que me gustan", "count": None}  # no sale en /feed/playlists
ANSI = re.compile(r"\x1b\[[0-9;]*m")


class DownloadCancelled(Exception):
    """El usuario pulsó Detener: se lanza desde el hook de progreso para cortar la descarga en curso."""


def playlist_url(playlist_id):
    return f"https://www.youtube.com/playlist?list={playlist_id}"


def video_url(video_id):
    return f"https://www.youtube.com/watch?v={video_id}"


def js_runtimes():
    """Los entornos de JavaScript que hay (deno, node o bun): YouTube pide resolver un desafío con uno de ellos, y
    sin él solo salen imágenes («Requested format is not available»)."""
    return {name: {"path": path} for name in ("deno", "node", "bun") if (path := shutil.which(name))}


def auth_opts(browser, cookies_file=None):
    """De dónde salen las cookies (un cookies.txt exportado, si se da, o las del navegador) y el entorno de JavaScript."""
    cookies = {"cookiefile": str(cookies_file)} if cookies_file else {"cookiesfrombrowser": (browser,)}
    runtimes = js_runtimes()
    return {**cookies, "js_runtimes": runtimes} if runtimes else cookies


def list_opts(browser, cookies_file=None):
    return {"quiet": True, "no_warnings": True, "extract_flat": True, "skip_download": True,
            **auth_opts(browser, cookies_file)}


def download_opts(music_dir, browser, ffmpeg_dir, hook, cookies_file=None):
    opts = {
        "format": "bestaudio/best",
        "postprocessors": [{"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "320"}],
        "outtmpl": os.path.join(str(music_dir), "%(title)s.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
        "progress_hooks": [hook],
        **auth_opts(browser, cookies_file),
    }
    if ffmpeg_dir:
        opts["ffmpeg_location"] = ffmpeg_dir
    return opts


def stream_opts(browser, cookies_file=None):
    """Para escuchar sin bajar: solo resolver el enlace directo del audio (m4a si hay: Windows lo reproduce siempre)."""
    return {"format": "bestaudio[ext=m4a]/bestaudio", "noplaylist": True, "quiet": True, "no_warnings": True,
            "skip_download": True, **auth_opts(browser, cookies_file)}


def stream_url(info):
    """(enlace directo, cabeceras que YouTube pide para él) de lo que devolvió yt-dlp."""
    url = (info or {}).get("url")
    if not url:
        raise ValueError("YouTube no dio un enlace de audio para esta canción")
    return url, dict((info or {}).get("http_headers") or {})


def playlists_from(info):
    """Las listas del usuario a partir de lo que devuelve /feed/playlists (más «Me gusta», que no sale ahí)."""
    found = [dict(LIKED)]
    for entry in (info or {}).get("entries") or []:
        if not entry or not entry.get("id") or entry["id"] == LIKED["id"]:
            continue
        found.append({"id": entry["id"], "title": entry.get("title") or entry["id"],
                      "count": entry.get("playlist_count") or entry.get("n_entries")})
    return found


def songs_from(info):
    songs = []
    for entry in (info or {}).get("entries") or []:
        if not entry or not entry.get("id"):
            continue
        songs.append({"id": entry["id"], "title": entry.get("title") or entry["id"],
                      "duration": int(entry["duration"]) if entry.get("duration") else None})
    return songs


def percent(d):
    """0-99 de un diccionario de progreso de yt-dlp (el 100 llega al terminar, tras convertir a MP3)."""
    total = d.get("total_bytes") or d.get("total_bytes_estimate")
    if not total:
        return 0
    return min(99, int(d.get("downloaded_bytes", 0) * 100 / total))


def final_path(info, ydl):
    """Dónde quedó el MP3 tras convertirlo."""
    for item in (info or {}).get("requested_downloads") or []:
        if item.get("filepath"):
            return item["filepath"]
    return os.path.splitext(ydl.prepare_filename(info))[0] + ".mp3"


def friendly_error(exc, browser):
    text = ANSI.sub("", str(exc)).strip()
    low = text.lower()
    if "dpapi" in low or ("cookie" in low and ("database" in low or "decrypt" in low or "permission" in low)):
        return (f"No se pudieron leer las cookies de {browser}: exporta un cookies.txt a "
                r"%APPDATA%\Kyora\cookies.txt, o usa Firefox en music.browser")
    if "401" in low or "unauthorized" in low or "403" in low or "forbidden" in low or "sign in" in low or "login" in low:
        return "YouTube necesita cookies nuevas: agrégalas con el botón"
    if "private" in low:
        return f"Inicia sesión en YouTube con {browser} (o la lista es privada)"
    if "requested format is not available" in low or "challenge" in low:
        return "YouTube pide Node.js o Deno para resolver su desafío: instala Node.js (winget install OpenJS.NodeJS.LTS)"
    if "ffmpeg" in low or "ffprobe" in low:
        return "Falta FFmpeg"
    if "unable to download" in low or "getaddrinfo" in low or "urlopen" in low:
        return "Sin conexión con YouTube"
    return text.removeprefix("ERROR: ")[:160] or "Error desconocido"


def find_ffmpeg():
    """Carpeta de ffmpeg.exe (en el PATH o donde lo deja winget), o None."""
    found = shutil.which("ffmpeg")
    if found:
        return os.path.dirname(found)
    base = os.environ.get("LOCALAPPDATA")
    if base:
        pattern = os.path.join(base, "Microsoft", "WinGet", "Packages", "Gyan.FFmpeg*", "**", "bin", "ffmpeg.exe")
        for path in glob.glob(pattern, recursive=True):
            return os.path.dirname(path)
    return None

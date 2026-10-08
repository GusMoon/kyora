import os
import json
from pathlib import Path
import yt_dlp
from colorama import init, Fore, Style

# Inicializar colorama para Windows
init(autoreset=True)


def get_js_runtime_opts() -> dict:
    """
    Opciones de yt-dlp para resolver los retos de firma/n de YouTube (EJS).
    Usa el binario de Deno instalado dentro del .venv (paquete pip `deno`),
    sin depender del Node.js global del sistema.
    """
    opts = {}
    try:
        import deno  # paquete pip que trae el ejecutable de Deno
        deno_bin = deno.find_deno_bin()
        if deno_bin and os.path.exists(deno_bin):
            opts['js_runtimes'] = {'deno': {'path': str(deno_bin)}}
    except Exception:
        pass  # yt-dlp intentará encontrar 'deno' en el PATH
    return opts

class MP3InstallerEcosystem:
    """
    Ecosistema para descargar listas de reproducción de YouTube en formato MP3
    utilizando cookies del navegador para evitar restricciones de la API.
    """
    def __init__(self, config_path: str = None):
        if config_path is None:
            # Default to the config folder
            base_dir = Path(__file__).parent
            self.config_path = base_dir / "mp3installer_config.json"
        else:
            self.config_path = Path(config_path)
            
        self.config = self._load_config()
        self.download_path = Path(self.config.get("download_path", str(Path.home() / "Music" / "KioraDownloads")))
        self.browser = self.config.get("browser_for_cookies", "chrome")
        self.audio_format = self.config.get("audio_format", "mp3")
        self.audio_quality = self.config.get("audio_quality", "320")

    def _load_config(self) -> dict:
        try:
            if self.config_path.exists():
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            else:
                print(f"{Fore.YELLOW}Advertencia: Archivo de configuración no encontrado en {self.config_path}. Usando valores por defecto.{Style.RESET_ALL}")
                return {}
        except Exception as e:
            print(f"{Fore.RED}Error al leer configuración: {e}{Style.RESET_ALL}")
            return {}

    def download_playlist(self, url: str):
        """Descarga la lista de reproducción usando cookies del navegador."""
        self.download_path.mkdir(parents=True, exist_ok=True)
        
        ydl_opts = {
            'format': 'bestaudio/best',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': self.audio_format,
                'preferredquality': self.audio_quality,
            }],
            'outtmpl': str(self.download_path / '%(playlist_index)s - %(title)s.%(ext)s'),
            'quiet': False,
            'nocheckcertificate': True,
            'yesplaylist': True,          # Forzar descarga de playlist
            'extract_flat': False,        # Descargar el contenido, no solo extraer los metadatos
            'ignoreerrors': True,         # Ignorar videos que no estén disponibles o sean privados
            **get_js_runtime_opts(),
        }
        
        if self.browser.endswith('.txt'):
            ydl_opts['cookiefile'] = self.browser
        else:
            ydl_opts['cookiesfrombrowser'] = (self.browser, )

        
        try:
            print(f"\n{Fore.CYAN}📥 Iniciando descarga de la lista de reproducción o video...")
            print(f"{Fore.YELLOW}🌐 Usando cookies del navegador: {self.browser}")
            print(f"{Fore.YELLOW}📂 Guardando en: {self.download_path}\n")
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([url])
                
            print(f"\n{Fore.GREEN}✅ ¡Descarga completada exitosamente!")
        except Exception as e:
            print(f"\n{Fore.RED}❌ Error durante la descarga: {str(e)}")

    def download_song(self, url: str, progress_hook=None) -> bool:
        """Descarga una sola canción y retorna True si fue exitoso."""
        self.download_path.mkdir(parents=True, exist_ok=True)
        
        ydl_opts = {
            'format': 'bestaudio/best',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': self.audio_format,
                'preferredquality': self.audio_quality,
            }],
            'outtmpl': str(self.download_path / '%(title)s.%(ext)s'),
            'quiet': True,
            'nocheckcertificate': True,
            'noplaylist': True,
            'ignoreerrors': True,
            **get_js_runtime_opts(),
        }
        
        if progress_hook:
            ydl_opts['progress_hooks'] = [progress_hook]
        
        if self.browser.endswith('.txt'):
            ydl_opts['cookiefile'] = self.browser
        else:
            ydl_opts['cookiesfrombrowser'] = (self.browser, )
            
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                error_code = ydl.download([url])
                return error_code == 0
        except Exception:
            return False

if __name__ == "__main__":
    # Prueba rápida interactiva del ecosistema
    installer = MP3InstallerEcosystem()
    
    print(f"{Fore.MAGENTA}{Style.BRIGHT}")
    print("=" * 60)
    print("  🎵 KIORA MP3 INSTALLER ECOSYSTEM 🎵")
    print("=" * 60)
    print(f"{Style.RESET_ALL}")
    
    while True:
        try:
            print(f"{Fore.YELLOW}{'─' * 60}")
            url = input(f"{Fore.WHITE}Ingresa la URL de la lista de reproducción o video (o 'q' para salir): {Style.RESET_ALL}").strip()
            
            if url.lower() in ['q', 'salir', 'exit']:
                print(f"\n{Fore.MAGENTA}👋 ¡Hasta pronto!")
                break
                
            if not url:
                continue
                
            installer.download_playlist(url)
            
        except KeyboardInterrupt:
            print(f"\n\n{Fore.MAGENTA}👋 Proceso interrumpido. ¡Hasta pronto!")
            break

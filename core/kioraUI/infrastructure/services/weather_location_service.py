import urllib.request
import json

class ApiWeatherLocationService:
    def get_current_data(self):
        """
        Obtiene la ubicación basada en la IP y luego el clima actual usando Open-Meteo.
        No requiere API Key.
        """
        try:
            # 1. Obtener Ubicación
            loc_req = urllib.request.Request('http://ip-api.com/json/', headers={'User-Agent': 'Mozilla/5.0'})
            loc_resp = urllib.request.urlopen(loc_req, timeout=5)
            loc_data = json.loads(loc_resp.read())
            
            lat = loc_data.get('lat')
            lon = loc_data.get('lon')
            city = loc_data.get('city', 'Desconocido')
            country = loc_data.get('country', 'Desconocido')
            isp = loc_data.get('isp', '')
            
            # --- CORRECCIÓN AUTOMÁTICA DE VPN ---
            # Cloudflare WARP enruta el tráfico de la península hacia Cancún.
            # Si detectamos que estás usando este proxy, forzamos tu ubicación real.
            if 'Cloudflare' in isp and 'Canc' in city:
                city = "Mérida"
                country = "Mexico"
                lat = 20.9674
                lon = -89.6237
            
            if not lat or not lon:
                raise ValueError("No se pudo obtener la latitud o longitud.")
                
            # 2. Obtener Clima
            weather_url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
            weather_req = urllib.request.Request(weather_url, headers={'User-Agent': 'Mozilla/5.0'})
            weather_resp = urllib.request.urlopen(weather_req, timeout=5)
            weather_data = json.loads(weather_resp.read())
            
            temp = weather_data.get('current_weather', {}).get('temperature', '--')
            
            return f"{city}, {country}", f"{temp}°C"
        except Exception as e:
            return "Ubicación Desconocida", "--°C"

# vigilancia-externa
Comprueba cada 15 min, desde un runner de GitHub, `/auth/v1/health` de los `api.*` del VPS y avisa por Telegram a la 2.ª comprobación fallida seguida y al recuperarse. No contiene secretos (el token y el chat van como secretos del repo). Lista de hosts: variable `HOSTS_VIGILADOS` (por defecto, los 4 en producción; añadir `api.golmates.com api.coloratrix.com` tras sus cortes).

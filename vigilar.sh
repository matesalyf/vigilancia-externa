#!/usr/bin/env bash
# Vigilancia externa del VPS: pide /auth/v1/health de cada api.* desde un runner de GitHub.
# Avisa por Telegram a la 2.ª comprobación fallida seguida y otra vez al recuperarse.
# Estado en estado/estado.json (solo se escribe cuando cambia algo).
# Variables: HOSTS (lista separada por espacios), RUTA (por defecto /auth/v1/health),
#            TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (secretos; si faltan, solo imprime),
#            LATIDO_URL (opcional: fichero con un epoch UTC que el VPS actualiza), LATIDO_MAX_H (26)
set -u
HOSTS="${HOSTS:?falta HOSTS}"
RUTA="${RUTA:-/auth/v1/health}"
ESTADO="${ESTADO:-estado/estado.json}"
mkdir -p "$(dirname "$ESTADO")"
[ -s "$ESTADO" ] || echo '{"hosts":{},"latido_alertado":false,"tocado":"1970-01-01"}' > "$ESTADO"
ORIG="$(cat "$ESTADO")"
EST="$ORIG"

avisar() {
  echo "AVISO: $1"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -o /dev/null --max-time 20 --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=$1" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      || echo "no se pudo enviar a Telegram"
  fi
}

for h in $HOSTS; do
  cod="000"
  for intento in 1 2; do   # un reintento en la misma pasada, para no confundir un parpadeo con una caída
    cod="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${h}${RUTA}" || true)"
    case "$cod" in 200|401|403) break ;; esac
    sleep 5
  done
  fallos="$(echo "$EST" | jq -r --arg h "$h" '.hosts[$h].fallos // 0')"
  alertado="$(echo "$EST" | jq -r --arg h "$h" '.hosts[$h].alertado // false')"
  case "$cod" in
    200|401|403)
      echo "OK   $h $cod"
      if [ "$alertado" = "true" ]; then
        avisar "✅ Recuperado: https://${h}${RUTA} vuelve a responder (HTTP $cod)."
      fi
      EST="$(echo "$EST" | jq --arg h "$h" '.hosts[$h]={fallos:0,alertado:false}')" ;;
    *)
      fallos=$((fallos+1))
      echo "FALLO $h $cod (seguidos: $fallos)"
      if [ "$fallos" -ge 2 ] && [ "$alertado" != "true" ]; then
        avisar "🚨 VPS: ${h}${RUTA} no responde (HTTP $cod) en $fallos comprobaciones seguidas, desde un runner de GitHub. Si cae el servidor entero, la vigilancia interna no avisa: esto sí."
        alertado=true
      fi
      EST="$(echo "$EST" | jq --arg h "$h" --argjson f "$fallos" --argjson a "$alertado" '.hosts[$h]={fallos:$f,alertado:$a}')" ;;
  esac
done

# Latido (opcional): el VPS publica un epoch; si tiene más de LATIDO_MAX_H horas, avisa una vez.
if [ -n "${LATIDO_URL:-}" ]; then
  ult="$(curl -s --max-time 20 "$LATIDO_URL" | tr -dc '0-9' | head -c 12)"
  max=$(( ${LATIDO_MAX_H:-26} * 3600 )); ahora="$(date -u +%s)"
  al="$(echo "$EST" | jq -r '.latido_alertado')"
  if [ -z "$ult" ] || [ $((ahora-ult)) -gt "$max" ]; then
    if [ "$al" != "true" ]; then
      avisar "🚨 VPS sin latido: no hay señal del servidor desde hace más de ${LATIDO_MAX_H:-26} h."
      EST="$(echo "$EST" | jq '.latido_alertado=true')"
    fi
  elif [ "$al" = "true" ]; then
    avisar "✅ El latido del VPS ha vuelto."
    EST="$(echo "$EST" | jq '.latido_alertado=false')"
  fi
fi

# Mantener vivo el repo público (GitHub desactiva los programados tras 60 días sin actividad): se toca cada ~20 días
hoy="$(date -u +%F)"
if [ $(( ( $(date -u -d "$hoy" +%s) - $(date -u -d "$(echo "$EST" | jq -r .tocado)" +%s) ) / 86400 )) -ge 20 ]; then
  EST="$(echo "$EST" | jq --arg d "$hoy" '.tocado=$d')"
fi
if [ "$(echo "$EST" | jq -S .)" != "$(echo "$ORIG" | jq -S .)" ]; then echo "$EST" | jq . > "$ESTADO"; echo "estado cambiado"; fi

#!/bin/bash

# ==============================================================================
# Script de Instalación Interactiva de Nextcloud 34 (Calificación A+)
# Entorno: Ubuntu Server 26.04 LTS | MariaDB 11.8 | Apache 2.4 | PHP 8.5
# Características: Automatización de Certbot y Directorio de Datos Seguro Aislado
# Autor: wfhgdev / Ing. William H.
# Fecha: Junio 2026
# ==============================================================================

# Modifica el comportamiento de las tuberías (pipelines) para mejorar la detección de errores
set -Eeuo pipefail

# Colores para la trazabilidad en consola
export NC='\033[0m'
export VERDE='\033[0;32m'
export CYAN='\033[0;36m'
export AMARILLO='\033[1;33m'
export ROJO='\033[0;31m'
trap 'echo -e "${ROJO}[ERROR] Instalación abortada en la línea $LINENO.${NC}"' ERR

# --- Funciones
info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

ok() {
    echo -e "${VERDE}[OK] $1${NC}"
}

warning() {
    echo -e "${AMARILLO}[ADVERTENCIA] $1${NC}"
}

error_exit() {
    echo -e "${ROJO}[ERROR] $1${NC}"
    exit 1
}

configurar_php() {
    local parametro=$1
    local valor=$2

    if grep -q "^${parametro}" "$PHP_INI"; then
        sed -i "s|^${parametro}.*|${parametro}=${valor}|" "$PHP_INI"
    else
        echo "${parametro}=${valor}" >> "$PHP_INI"
    fi
}

seleccionar_zona_horaria() {
    echo ""
    info "Seleccione su país o región para configurar la zona horaria y la región de Nextcloud"

    echo "  1) España      (Europe/Madrid)"
    echo "  2) Colombia    (America/Bogota)"
    echo "  3) México      (America/Mexico_City)"
    echo "  4) Argentina   (America/Argentina/Buenos_Aires)"
    echo "  5) Venezuela   (America/Caracas)"
    echo "  6) Ecuador     (America/Guayaquil)"
    echo "  7) Perú        (America/Lima)"
    echo "  8) Bolivia     (America/La_Paz)"
    echo "  9) Chile       (America/Santiago)"
    echo " 10) Personalizado (Ingresar manualmente zona horaria)"

    while true; do
        read -rp "Seleccione una opción [1]: " TZ_OPTION
        TZ_OPTION=${TZ_OPTION:-1}

        case "$TZ_OPTION" in
            1)
                TIMEZONE="Europe/Madrid"
                NEXTCLOUD_LOCALE="es_ES"
                break
                ;;
            2)
                TIMEZONE="America/Bogota"
                NEXTCLOUD_LOCALE="es_CO"
                break
                ;;
            3)
                TIMEZONE="America/Mexico_City"
                NEXTCLOUD_LOCALE="es_MX"
                break
                ;;
            4)
                TIMEZONE="America/Argentina/Buenos_Aires"
                NEXTCLOUD_LOCALE="es_AR"
                break
                ;;
            5)
                TIMEZONE="America/Caracas"
                NEXTCLOUD_LOCALE="es_VE"
                break
                ;;
            6)
                TIMEZONE="America/Guayaquil"
                NEXTCLOUD_LOCALE="es_EC"
                break
                ;;
            7)
                TIMEZONE="America/Lima"
                NEXTCLOUD_LOCALE="es_PE"
                break
                ;;
            8)
                TIMEZONE="America/La_Paz"
                NEXTCLOUD_LOCALE="es_BO"
                break
                ;;
            9)
                TIMEZONE="America/Santiago"
                NEXTCLOUD_LOCALE="es_CL"
                break
                ;;
            10)
                while true; do
                    read -rp "Ingrese la zona horaria (ej: America/Panama o Asia/Tokyo): " TIMEZONE

                    if timedatectl list-timezones | grep -Fxq "$TIMEZONE"; then
                        break
                    else
                        warning "La zona horaria ingresada no es válida. Intente nuevamente."
                    fi
                done

                # Para una zona horaria personalizada se usa español genérico
                NEXTCLOUD_LOCALE="es"
                break
                ;;
            *)
                warning "Opción inválida. Debe seleccionar un número del 1 al 10."
                ;;
        esac
    done

    # Configurar la zona horaria del sistema
    if timedatectl set-timezone "$TIMEZONE"; then
        ok "Zona horaria configurada: $TIMEZONE"
    else
        error_exit "No se pudo configurar la zona horaria del sistema."
    fi

    ok "Región de Nextcloud configurada: $NEXTCLOUD_LOCALE"
    echo ""
}

# --- Crear log
LOG_FILE="/var/log/ncInstall.log"
exec > >(tee -a "$LOG_FILE") 2>&1
info "Inicio de instalación. Log almacenado en $LOG_FILE"

# --- FASE 1: VERIFICACIONES DE CONTROL DE CALIDAD ---
echo -e "${CYAN}[1/11] Ejecutando pruebas de control de calidad del entorno...${NC}"

# Verificar privilegios de root
if [ "$EUID" -ne 0 ]; then
    error_exit "Este script debe ejecutarse con privilegios de root (sudo)."
    exit 1
fi

# Verificar versión de Ubuntu Server (Debe ser 26.04)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$VERSION_ID" != "26.04" ]; then
		error_exit "Este script está diseñado exclusivamente para Ubuntu 26.04 LTS."
        exit 1
    fi
else
	error_exit "No se pudo determinar la distribución del sistema operativo."
    exit 1
fi

# Verificar recursos mínimos (2GB RAM mínimos para producción)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 2000 ]; then
    warning "Se detectaron menos de 2GB de RAM ($TOTAL_RAM MB). Nextcloud podría tener problemas de rendimiento."
    read -p "¿Desea continuar de todos modos? (s/n): " CONTINUAR
    [[ "$CONTINUAR" != "s" ]] && exit 1
fi

# Verificar espacio libre en disco al inicio
DISK_FREE=$(df / --output=avail | tail -1)
DISK_FREE_GB=$((DISK_FREE / 1024 / 1024))

if [ "$DISK_FREE_GB" -lt 10 ]; then
    warning "Espacio libre bajo: ${DISK_FREE_GB} GB disponibles. Se recomienda un mínimo de 10 GB."
fi

ok "Entorno validado con éxito."
echo ""

# --- FASE 2: ASISTENTE INTERACTIVO DE RECOPILACIÓN DE DATOS ---
echo -e "${CYAN}[2/11] Iniciando asistente interactivo de configuración...${NC}"

# Solicitar dominio o IP pública
while :; do
    read -p "Ingrese el nombre de dominio de su servidor (ej: nube.midominio.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        warning "El dominio no puede estar vacío."
    else
        break
    fi
done

info "Verificando resolución DNS del dominio..."

if getent hosts "$DOMAIN" > /dev/null; then
    ok "El dominio resuelve correctamente."
else
    warning "El dominio aún no resuelve. Let's Encrypt podría fallar."
fi

# Selección de zona horaria del servidor
seleccionar_zona_horaria

# Preguntar si se desea automatizar SSL con Let's Encrypt
while :; do
    read -p "¿Desea generar un certificado SSL válido y gratuito con Let's Encrypt? (s/n): " CONFIRM_SSL
    if [[ "$CONFIRM_SSL" =~ ^[SsNn]$ ]]; then
        if [[ "$CONFIRM_SSL" =~ ^[Ss]$ ]]; then
            ENABLE_LETSENCRYPT=true
            while :; do
                read -p "Ingrese su correo electrónico para las alertas de renovación de Let's Encrypt: " SSL_EMAIL
                if [ -z "$SSL_EMAIL" ]; then
					warning "El correo electrónico es obligatorio para el registro de Let's Encrypt."
                else
                    break
                fi
            done
        else
            ENABLE_LETSENCRYPT=false
        fi
        break
    else
        echo -e "${ROJO}Por favor, responda 's' para sí o 'n' para no.${NC}"
    fi
done

# Datos del Administrador de Nextcloud
while :; do
    read -p "Defina el nombre del usuario administrador de Nextcloud [admin]: " NC_ADMIN
    NC_ADMIN=${NC_ADMIN:-admin}
    [[ "$NC_ADMIN" == *" "* ]] && echo -e "${ROJO}El usuario no puede contener espacios.${NC}" || break
done

while :; do
    read -s -p "Defina la contraseña del administrador de Nextcloud (mínimo 8 caracteres): " NC_PASS
    echo ""
    if [ ${#NC_PASS} -lt 8 ]; then
        echo -e "${ROJO}Contraseña demasiado corta.${NC}"
    else
        break
    fi
done

# Datos de la Base de Datos
read -p "Nombre de la base de datos MariaDB [nextcloud_db]: " DB_NAME
DB_NAME=${DB_NAME:-nextcloud_db}
read -p "Usuario de la base de datos MariaDB [nextcloud_user]: " DB_USER
DB_USER=${DB_USER:-nextcloud_user}

while :; do
    read -s -p "Defina la contraseña para el usuario de la base de datos (mínimo 8 caracteres): " DB_PASS
    echo ""

    # Verificar que no esté vacía
    if [ -z "$DB_PASS" ]; then
        echo -e "${ROJO}[ERROR] La contraseña de la base de datos es obligatoria.${NC}"
        continue
    fi

    # Verificar longitud mínima
    if [ ${#DB_PASS} -lt 8 ]; then
        echo -e "${ROJO}[ERROR] La contraseña debe tener al menos 8 caracteres.${NC}"
        continue
    fi

    # Bloquear caracteres que pueden romper el script o la sentencia SQL
    if [[ "$DB_PASS" =~ [\'\"\`\$\\] ]]; then
        echo -e "${ROJO}[ERROR] La contraseña contiene caracteres no permitidos.${NC}"
        echo -e "${AMARILLO}Caracteres prohibidos: '  \"  \`  \$  \\ ${NC}"
        continue
    fi

    # Solicitar confirmación
    read -s -p "Confirme nuevamente la contraseña: " DB_PASS_CONFIRM
    echo ""

    # Comparar ambas contraseñas
    if [ "$DB_PASS" != "$DB_PASS_CONFIRM" ]; then
        echo -e "${ROJO}[ERROR] Las contraseñas no coinciden. Inténtelo nuevamente.${NC}"
        continue
    fi

    # Si todas las validaciones son correctas, salir del bucle
    break

done

# Detectar dirección IP local principal del servidor
LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

if [ -n "$LOCAL_IP" ]; then
    info "Dirección IP local detectada: $LOCAL_IP"
else
    warning "No fue posible detectar la dirección IP local del servidor."
fi

echo -e "${VERDE}[OK] Datos recopilados de forma segura.${NC}\n"

# --- FASE 3: ACTUALIZACIÓN E INSTALACIÓN DEL STACK (LAMP + REDIS + CERTBOT) ---
echo -e "${CYAN}[3/11] Actualizando repositorios e instalando paquetes del sistema...${NC}"
if apt-get update -y && apt-get upgrade -y; then
    ok "Repositorios actualizados correctamente."
else
    error_exit "Falló la actualización de APT. Revise repositorios externos, claves GPG o conexión a Internet."
fi

echo -e "${CYAN}Instalando Apache 2.4, MariaDB 11.8, PHP 8.5, Redis y Certbot...${NC}"
if apt-get install -y apache2 mariadb-server mariadb-client redis-server curl unzip bzip2 sudo ssl-cert \
php8.5 php8.5-fpm php8.5-mysql php8.5-intl php8.5-curl php8.5-gd php8.5-xml php8.5-zip \
php8.5-mbstring php8.5-bcmath php8.5-gmp php8.5-imagick php8.5-opcache php8.5-redis php8.5-bz2 \
certbot python3-certbot-apache
then
    ok "Stack LAMP, Redis y herramientas SSL instaladas correctamente."
else
    error_exit "Falló la instalación de paquetes del sistema. Revise disponibilidad de repositorios."
fi

# --- FASE 4: CONFIGURACIÓN SEGURA DE MARIADB 11.8 ---
echo -e "${CYAN}[4/11] Configurando el motor de base de datos MariaDB 11.8...${NC}"
if ! command -v mariadb >/dev/null 2>&1; then
    error_exit "MariaDB no está instalado correctamente."
fi
systemctl start mariadb
systemctl enable mariadb

# Verificar que MariaDB esté activo antes de continuar
if systemctl is-active --quiet mariadb; then
    echo -e "${VERDE}[OK] Servicio MariaDB iniciado correctamente.${NC}"
else
    echo -e "${ROJO}[ERROR] MariaDB no pudo iniciarse correctamente.${NC}"
    echo -e "${AMARILLO}[INFO] Revise el estado con: systemctl status mariadb${NC}"
    exit 1
fi

mariadb -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

if mariadb -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
...
EOF
then
    ok "Base de datos y privilegios creados correctamente."
else
    error_exit "No se pudo inicializar MariaDB."
fi

# --- FASE 5: OPTIMIZACIÓN DE PHP 8.5 PARA CALIFICACIÓN A+ ---
cp "$PHP_INI" "${PHP_INI}.bak"
ok "Copia de seguridad de php.ini creada."
echo -e "${CYAN}[5/11] Aplicando optimizaciones de rendimiento y seguridad en PHP 8.5...${NC}"
PHP_INI="/etc/php/8.5/fpm/php.ini"

if [ -f "$PHP_INI" ]; then
    sed -i "s|memory_limit =.*|memory_limit = 512M|g" "$PHP_INI"
    sed -i "s|upload_max_filesize =.*|upload_max_filesize = 10G|g" "$PHP_INI"
    sed -i "s|post_max_size =.*|post_max_size = 10G|g" "$PHP_INI"
    sed -i "s|max_execution_time =.*|max_execution_time = 3600|g" "$PHP_INI"
    configurar_php date.timezone "$TIMEZONE"
    
    # Configuración estricta de OPcache requerida por Nextcloud
	configurar_php opcache.enable 1
    configurar_php opcache.enable_cli 1
    configurar_php opcache.interned_strings_buffer 16
    configurar_php opcache.max_accelerated_files 10000
    configurar_php opcache.memory_consumption 128
    configurar_php opcache.save_comments 1
    configurar_php opcache.revalidate_freq 1
    
    systemctl restart php8.5-fpm
	# Verificar que PHP-FPM esté activo
    if systemctl is-active --quiet php8.5-fpm; then
        echo -e "${VERDE}[OK] PHP-FPM reiniciado y configurado correctamente.${NC}"
        else
        echo -e "${ROJO}[ERROR] PHP-FPM no pudo iniciarse correctamente.${NC}"
        echo -e "${AMARILLO}[INFO] Revise el estado con: systemctl status php8.5-fpm${NC}"
        exit 1
    fi
    echo -e "${VERDE}[OK] Directivas OPcache y límites de memoria asignados en php.ini.${NC}\n"
else
    echo -e "${ROJO}[ERROR] No se pudo localizar el archivo php.ini en la ruta esperada.${NC}"
    exit 1
fi

# --- FASE 6: DESPLIEGUE DEL CÓDIGO FUENTE Y AISLAMIENTO DE DATOS (SEGURIDAD DEFENSA EN PROFUNDIDAD) ---
echo -e "${CYAN}[6/11] Descargando Nextcloud 34 y estructurando directorios seguros...${NC}"
NC_PATH="/var/www/nextcloud"
NC_DATA_PATH="/var/nextcloud-data" # Definición del directorio de almacenamiento aislado del entorno web

# Limpieza y despliegue del binario web
rm -rf "$NC_PATH"
if curl -fsSL https://download.nextcloud.com/server/releases/latest-34.tar.bz2 -o /tmp/nextcloud.tar.bz2
then
    ok "Paquete de Nextcloud descargado correctamente."
else
    error_exit "No se pudo descargar Nextcloud desde el servidor oficial."
fi

if tar -xjf /tmp/nextcloud.tar.bz2 -C /var/www/; then
    ok "Archivos de Nextcloud desplegados correctamente."
	rm -f /tmp/nextcloud.tar.bz2
    ok "Archivo temporal de instalación eliminado."
else
    error_exit "Falló la extracción del paquete de Nextcloud."
fi

# Crear e implementar las directivas de seguridad para la carpeta de almacenamiento externa
mkdir -p "$NC_DATA_PATH"
chown -R www-data:www-data "$NC_DATA_PATH"
chmod -R 770 "$NC_DATA_PATH" # Solo www-data y root tienen acceso total

# Permisos para el árbol web
chown -R www-data:www-data "$NC_PATH"
chmod -R 755 "$NC_PATH"
echo -e "${VERDE}[OK] Código web en $NC_PATH. Almacenamiento privado blindado en $NC_DATA_PATH.${NC}\n"

# --- FASE 7: INSTALACIÓN DESATENDIDA MEDIANTE INTERFAZ OCC ---
echo -e "${CYAN}[7/11] Ejecutando el proceso de instalación core con OCC...${NC}"
cd "$NC_PATH"

sudo -u www-data php occ maintenance:install \
  --database="mysql" \
  --database-name="$DB_NAME" \
  --database-user="$DB_USER" \
  --database-pass="$DB_PASS" \
  --admin-user="$NC_ADMIN" \
  --admin-pass="$NC_PASS" \
  --data-dir="$NC_DATA_PATH" # Mapeo directo al directorio aislado externo

if sudo -u www-data php occ maintenance:install \
    --database="mysql" \
    ...
then
    ok "Instalación interna de Nextcloud completada con éxito."
else
    error_exit "Falló la instalación mediante la CLI OCC de Nextcloud."
fi

# --- FASE 8: INTEGRACIÓN DE CACHÉ DE MEMORIA RAM CON REDIS ---
echo -e "${CYAN}[8/11] Vinculando Redis Server para la gestión de bloqueos de archivos y caché...${NC}"
systemctl start redis-server
systemctl enable redis-server

# Verificar que Redis esté activo
if systemctl is-active --quiet redis-server; then
    echo -e "${VERDE}[OK] Redis Server iniciado correctamente.${NC}"
else
    echo -e "${ROJO}[ERROR] Redis Server no pudo iniciarse correctamente.${NC}"
    echo -e "${AMARILLO}[INFO] Revise el estado con: systemctl status redis-server${NC}"
    exit 1
fi

#sudo -u www-data php occ config:system:set memcache.local --value="\OC\Memcache\Redis"
if sudo -u www-data php occ config:system:set memcache.local --value="\OC\Memcache\Redis"; then
    ok "Memcache local configurado."
else
    error_exit "No se pudo configurar Redis en Nextcloud."
fi

#sudo -u www-data php occ config:system:set memcache.distributed --value="\OC\Memcache\Redis"
if sudo -u www-data php occ config:system:set memcache.distributed --value="\OC\Memcache\Redis"; then
    ok "Memcache distributed configurado."
else
    error_exit "No se pudo configurar Memcache distributed en Nextcloud."
fi

#sudo -u www-data php occ config:system:set memcache.locking --value="\OC\Memcache\Redis"
if sudo -u www-data php occ config:system:set memcache.locking --value="\OC\Memcache\Redis"; then
    ok "Memcache locking configurado."
else
    error_exit "No se pudo configurar Memcache locking en Nextcloud."
fi

#sudo -u www-data php occ config:system:set redis --value='{"host":"127.0.0.1","port":6379,"timeout":0.0}' --type=json
if sudo -u www-data php occ config:system:set redis --value='{"host":"127.0.0.1","port":6379,"timeout":0.0}' --type=json; then
    ok "Redis configurado."
else
    error_exit "No se pudo configurar Redis en Nextcloud."
fi

#sudo -u www-data php occ config:system:set overwrite.cli.url --value="https://$DOMAIN"
if sudo -u www-data php occ config:system:set overwrite.cli.url --value="https://$DOMAIN"; then
    ok "Overwrite cli url configurado."
else
    error_exit "No se pudo configurar Overwrite cli url en Nextcloud."
fi

# Establecer español como idioma predeterminado de Nextcloud
sudo -u www-data php occ config:system:set default_language --value="es"
ok "Idioma predeterminado de Nextcloud configurado en español."

# Configurar la región de Nextcloud
sudo -u www-data php occ config:system:set default_locale --value="$NEXTCLOUD_LOCALE"

# Se agrega el Dominio público Trusted Domain
sudo -u www-data php occ config:system:set trusted_domains 1 --value="$DOMAIN"

# Se agrega el Acceso por IP local al Trusted Domain 
if [ -n "$LOCAL_IP" ]; then
    sudo -u www-data php occ config:system:set trusted_domains 2 --value="$LOCAL_IP"
    ok "Acceso local por IP agregado a trusted_domains: $LOCAL_IP"
else
    warning "Se omitió la configuración de acceso por IP local."
fi

echo -e "${VERDE}[OK] Redis configurado como backend de caché de memoria RAM.${NC}\n"

# --- FASE 9: CONFIGURACIÓN DE VIRTUALHOSTS CON CABECERAS DE SEGURIDAD A+ ---
echo -e "${CYAN}[9/11] Creando configuraciones en Apache con directivas HSTS estrictas...${NC}"
VHOST_CONF="/etc/apache2/sites-available/nextcloud.conf"

a2enmod rewrite headers env dir mime ssl proxy proxy_fcgi setenvif mpm_event > /dev/null
a2enconf php8.5-fpm > /dev/null

cat <<EOF > "$VHOST_CONF"
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $NC_PATH

    # Redirección permanente a HTTPS para garantizar cifrado de extremo a extremo
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $NC_PATH

    # --- CERTIFICADOS SSL PROVISIONALES ---
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

    # --- CABECERAS ESTRICTAS PARA CALIFICACIÓN SEGURIDAD A+ ---
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Robots "noindex, nofollow"
    Header always set Referrer-Policy "no-referrer"

    # Redirecciones de descubrimiento de servicios requeridas por Nextcloud (.well-known)
    Redirect 301 /.well-known/carddav /remote.php/dav
    Redirect 301 /.well-known/caldav /remote.php/dav
    Redirect 301 /.well-known/webfinger /index.php/.well-known/webfinger
    Redirect 301 /.well-known/nodeinfo /index.php/.well-known/nodeinfo

    <Directory $NC_PATH/>
        Options +FollowSymlinks
        AllowOverride All

        <IfModule mod_dav.c>
            Dav off
        </IfModule>

        SetEnv HOME $NC_PATH
        SetEnv HTTP_HOME $NC_PATH
    </Directory>
</VirtualHost>
EOF

# Activar el sitio y reiniciar Apache temporalmente
a2ensite nextcloud.conf > /dev/null
a2dissite 000-default.conf > /dev/null

# Comprobar sintaxis de Apache antes de reiniciar
if apachectl configtest; then
    systemctl restart apache2
else
    echo -e "${ROJO}[ERROR] La configuración de Apache contiene errores de sintaxis.${NC}"
    exit 1
fi

# Validar que Apache esté funcionando
if systemctl is-active --quiet apache2; then
    echo -e "${VERDE}[OK] Apache 2.4 iniciado y configurado correctamente.${NC}"
else
    echo -e "${ROJO}[ERROR] Apache no pudo iniciar correctamente.${NC}"
    echo -e "${AMARILLO}[INFO] Revise la configuración con: apachectl configtest${NC}"
    echo -e "${AMARILLO}[INFO] Revise el servicio con: systemctl status apache2${NC}"
    exit 1
fi

echo -e "${VERDE}[OK] Base del servidor web configurada.${NC}\n"

# --- FASE 10: AUTOMATIZACIÓN DE CERTBOT Y LET'S ENCRYPT ---
echo -e "${CYAN}[10/11] Gestionando la automatización del certificado SSL...${NC}"

if [ "$ENABLE_LETSENCRYPT" = true ]; then
    echo -e "${CYAN}Solicitando certificado oficial a los servidores de Let's Encrypt para $DOMAIN...${NC}"
    
    # Ejecución de Certbot de manera no interactiva respetando la configuración previa de Apache
    certbot --apache --non-interactive --agree-tos --redirect \
        --keep-until-expiring \
        -m "$SSL_EMAIL" \
        -d "$DOMAIN"
    
    if certbot --apache --non-interactive --agree-tos --redirect \
        --keep-until-expiring \
        -m "$SSL_EMAIL" \
        -d "$DOMAIN"
    then
        ok "Certificado SSL emitido e instalado correctamente."
    else
        warning "Falló la verificación de Certbot. Verifique DNS, puertos 80/443 y firewall."
        warning "Se mantendrán los certificados autofirmados provisionales por seguridad."
    fi
else
    echo -e "${AMARILLO}[INFO] Omisión de Let's Encrypt solicitada por el usuario. Recuerde mapear sus llaves TLS manualmente.${NC}"
fi
echo ""

# --- FASE 11: TAREAS DE CONSOLIDACIÓN Y CRON DEL SISTEMA ---
echo -e "${CYAN}[11/11] Aplicando el modelo de permisos final, reparaciones de DB y configurando Cron del sistema...${NC}"

# Cambiar el método de tareas en segundo plano al modo óptimo (Cron)
sudo -u www-data php occ backgroundjob:setsystemcron

# Programación de la ejecución de las tareas en segundo plano de Nextcloud cada 5 minutos
crontab -u www-data -l 2>/dev/null | { cat; echo "*/5 * * * * php -f $NC_PATH/cron.php > /dev/null 2>&1"; } | crontab -u www-data -

# Indexación y reparaciones estructurales de la base de datos (Mitigación estricta de advertencias en panel de control)
sudo -u www-data php occ db:add-missing-indices --no-interaction
sudo -u www-data php occ db:add-missing-columns --no-interaction
sudo -u www-data php occ db:convert-filecache-bigint --no-interaction # Optimización BigInt

echo -e "${VERDE}======================================================================${NC}"
echo -e "${VERDE}             ¡INSTALACIÓN DE NEXTCLOUD COMPLETADA CON ÉXITO!          ${NC}"
echo -e "${VERDE}======================================================================${NC}"
if [ "$SSL_ENABLED" = true ]; then
    echo -e "${CYAN}Acceso público:${NC} https://${DOMAIN}"
    echo -e "${CYAN}Acceso local:${NC} https://${LOCAL_IP}"
else
    echo -e "${CYAN}Acceso público:${NC} http://${DOMAIN}"
    echo -e "${CYAN}Acceso local:${NC} http://${LOCAL_IP}"
fi
echo -e "${CYAN}Usuario Administrador Nextcloud:${NC} $NC_ADMIN"
echo -e "${CYAN}Directorio de datos Nextcloud:${NC} $NC_DATA_PATH"
echo -e "${CYAN}Base de datos MariaDB:${NC} ${DB_NAME}"
echo -e "${CYAN}Usuario de base de datos:${NC} ${DB_USER}"
echo -e "${CYAN}Región de Nextcloud:${NC} ${NEXTCLOUD_LOCALE}"
echo -e "${CYAN}Zona horaria:${NC} ${TIMEZONE}"

if [ "$ENABLE_LETSENCRYPT" = true ]; then
    echo -e "${VERDE}Estado de Seguridad:${NC} Certificado Let's Encrypt Activo - Calificación A+ Lista."
else
    echo -e "${AMARILLO}Estado de Seguridad:${NC} Usando certificado provisional. Instale llaves válidas para obtener A+."
fi
echo -e "${CYAN}Versión de Nextcloud:${NC} ${NEXTCLOUD_VERSION}"
echo -e "${CYAN}Versión de PHP:${NC} ${PHP_VERSION}"
echo -e "${CYAN}Versión de MariaDB:${NC} ${MARIADB_VERSION}"
echo -e "${CYAN}Archivo de registro:${NC} /var/log/ncInstall.log"
echo -e "${VERDE}======================================================================${NC}"

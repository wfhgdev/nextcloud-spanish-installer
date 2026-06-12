# Script de Instalación Automatizada y Segura de Nextcloud 34

Este repositorio contiene un script interactivo en Bash diseñado para desplegar de forma completamente automática, eficiente y segura un entorno de producción para **Nextcloud 34** en **Ubuntu Server 26.04 LTS**. 

A diferencia de los métodos de instalación estándar, este script aplica directivas estrictas de rendimiento y seguridad que garantizan una calificación de **Seguridad A+** y un panel de administración limpio, con todas las **marcas de verificación en verde (cero advertencias)** desde el primer inicio de sesión.

## 🚀 Características Principales

* **Stack Tecnológico de Vanguardia:** Configuración optimizada utilizando Apache 2.4, MariaDB 11.8, PHP 8.5 (FPM) y Redis Server.
* **Asistente Interactivo Seguro:** Recopila contraseñas de forma oculta enmascarando la entrada y valida que el entorno cumpla con los requisitos mínimos de hardware (mínimo 2GB de RAM) antes de proceder.
* **Automatización SSL Nativa:** Integración desatendida con Certbot y Let's Encrypt para la generación, instalación y renovación automática de certificados TLS válidos.
* **Procesamiento Eficiente en Segundo Plano:** Migración automática del sistema de tareas internas de Nextcloud hacia el `cron` nativo de Linux (programado minuciosamente cada 5 minutos) para evitar la degradación del rendimiento por peticiones web (AJAX).

## 🛡️ Mejoras de Seguridad (Defensa en Profundidad)

El script ha sido diseñado bajo estándares estrictos de endurecimiento (*hardening*) de servidores, destacando las siguientes implementaciones:

1. **Aislamiento del Directorio de Datos:** La carpeta física de almacenamiento de archivos se despliega en `/var/nextcloud-data`, quedando completamente fuera de la raíz pública del servidor web (`/var/www/nextcloud`). Se le asignan permisos restrictivos `770` para que exclusivamente el usuario del sistema `www-data` y *root* puedan interactuar con los datos.
2. **VirtualHost Aislado y Dedicado:** Se desactiva por completo el sitio por defecto de Apache (`000-default.conf`) y se genera un archivo de configuración único para el dominio. Esto mitiga el escaneo masivo de IPs y bloquea peticiones HTTP no autorizadas.
3. **Cabeceras de Seguridad Estrictas (Calificación A+):** Inyección nativa de directivas de seguridad en el servidor web, incluyendo:
   * **HSTS Extendido:** `Strict-Transport-Security "max-age=15552000; includeSubDomains; preload"` para forzar conexiones cifradas.
   * Protección contra *Clickjacking* y *MIME-Sniffing* (`X-Frame-Options` y `X-Content-Type-Options`).
   * Políticas de Referencia y Bloqueo de Indexación para motores de búsqueda externos (`Referrer-Policy` y `Robots`).

## ✅ Instalación con "Marca Verde" (Cero Advertencias)

El script soluciona de manera proactiva todos los dolores de cabeza comunes del panel de administración de Nextcloud tras una instalación limpia:

* **Conversión Estructural a BigInt:** Ejecuta preventivamente la conversión de las columnas críticas en la base de datos (`db:convert-filecache-bigint`). Esto evita que el contador de IDs de archivos colapse en sistemas de producción y elimina la advertencia de almacenamiento de enteros de 32 bits.
* **Reparación de Índices y Columnas:** Aplica `db:add-missing-indices` y `db:add-missing-columns` para optimizar las consultas SQL en MariaDB.
* **Descubrimiento de Servicios Integrado:** Configura correctamente las redirecciones `.well-known` (`carddav`, `caldav`, `webfinger`, `nodeinfo`) en las directivas de Apache para evitar errores de sincronización con clientes móviles y de escritorio.
* **Optimización de Memoria PHP:** Configura de manera estricta los valores requeridos para OPcache (`opcache.interned_strings_buffer`, `opcache.max_accelerated_files`, etc.) y eleva el límite de memoria a 512M en el archivo `php.ini` de PHP-FPM.

## 🛠️ Requisitos Previos

1. Un servidor con **Ubuntu Server 26.04 LTS** limpio (instalación base).
2. Privilegios de acceso como **root** o permisos de `sudo`.
3. Un **nombre de dominio** (ej: `nube.midominio.com`) con el registro DNS tipo **A** apuntando hacia la IP pública de tu servidor.
4. Puertos **80** y **443** abiertos en tu cortafuegos/enrutador.

## 💻 Cómo Ejecutar el Script

### :sheep: Metodo 2 (Clonación de repositorio)
Asegúrate de tener **Git** instalado, verifícalo con el comando `git --version`, de lo contrario puedes instalar **Git** (sistema de control de versiones) con el comando: `sudo apt install git`

```Shell
git clone https://github.com/wfhgdev/nc34_spa.git && cd nc34_spa && chmod +x ncInstall.sh && sudo ./ncInstall.sh

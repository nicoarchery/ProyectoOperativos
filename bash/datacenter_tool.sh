#!/usr/bin/env bash

readonly SCRIPT_VERSION="1.0.0"

show_menu() {
    echo "=============================================="
    echo " Data Center Administration Tool - BASH v$SCRIPT_VERSION"
    echo "=============================================="
    echo " 1. Usuarios del sistema y último login"
    echo " 2. Filesystems / Discos conectados"
    echo " 3. Archivos más grandes en un filesystem"
    echo " 4. Memoria libre y swap"
    echo " 5. Backup de directorio a USB"
    echo "----------------------------------------------"
    echo " 0. Salir"
    echo "=============================================="
    echo
}

option_1() {
    echo "=============================================="
    echo " USUARIOS DEL SISTEMA Y ÚLTIMO LOGIN"
    echo "=============================================="
    printf "%-20s %-15s %s\n" "USUARIO" "PUERTO" "ÚLTIMO LOGIN"
    echo "----------------------------------------------"

    local lastlogin_output
    lastlogin_output=$(lastlog 2>/dev/null) || {
        echo "Error: no se pudo ejecutar 'lastlog' (comando no encontrado o sin permisos)." >&2
        return 1
    }

    while IFS= read -r line; do
        local user port rest
        IFS=' ' read -r user port rest <<< "$line"
        [[ "$user" == "Username" ]] && continue

        local uid
        uid=$(id -u "$user" 2>/dev/null) || continue

        if [[ "$uid" -ge 1000 && "$uid" -lt 65534 ]]; then
            if echo "$rest" | grep -qi "never"; then
                printf "%-20s %-15s %s\n" "$user" "-" "Nunca ingresó"
            else
                printf "%-20s %-15s %s\n" "$user" "$port" "$port $rest"
            fi
        fi
    done <<< "$lastlogin_output"

    echo "----------------------------------------------"
    echo
}

option_2() {
    echo "=============================================="
    echo " FILESYSTEMS / DISCOS CONECTADOS"
    echo "=============================================="
    printf "%-25s %-18s %-18s %s\n" "FILESYSTEM" "TAMAÑO (bytes)" "ESPACIO LIBRE" "MONTADO EN"
    echo "----------------------------------------------"

    df -B1 -x tmpfs -x devtmpfs -x efivarfs -x overlay 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        local fs size used avail use_pct mount
        read -r fs size used avail use_pct mount <<< "$line"

        if [[ -n "$mount" && "$mount" != /* ]]; then
            local rest
            read -r rest <<< "$line"
            continue
        fi

        if [[ "$fs" == "none" || "$fs" == "tmpfs" || "$fs" == "devtmpfs" ]]; then
            continue
        fi

        printf "%-25s %'18d %'18d %s\n" "$fs" "$size" "$avail" "$mount"
    done

    echo "----------------------------------------------"
    echo
}

option_4() {
    echo "=============================================="
    echo " MEMORIA LIBRE Y SWAP"
    echo "=============================================="

    if [[ ! -r /proc/meminfo ]]; then
        echo "Error: no se puede leer /proc/meminfo." >&2
        return 1
    fi

    local mem_total mem_free swap_total swap_free

    mem_total=$(grep -E '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_free=$(grep -E '^MemFree:' /proc/meminfo | awk '{print $2}')
    swap_total=$(grep -E '^SwapTotal:' /proc/meminfo | awk '{print $2}')
    swap_free=$(grep -E '^SwapFree:' /proc/meminfo | awk '{print $2}')

    local mem_total_bytes=$((mem_total * 1024))
    local mem_free_bytes=$((mem_free * 1024))
    local mem_used_bytes=$((mem_total_bytes - mem_free_bytes))
    local mem_used_pct=0
    if [[ "$mem_total_bytes" -gt 0 ]]; then
        mem_used_pct=$((mem_used_bytes * 100 / mem_total_bytes))
    fi

    local swap_total_bytes=$((swap_total * 1024))
    local swap_free_bytes=$((swap_free * 1024))
    local swap_used_bytes=$((swap_total_bytes - swap_free_bytes))
    local swap_used_pct=0
    if [[ "$swap_total_bytes" -gt 0 ]]; then
        swap_used_pct=$((swap_used_bytes * 100 / swap_total_bytes))
    fi

    echo " MEMORIA RAM"
    echo "  Total:  $(numfmt --to=iec "$mem_total_bytes")  ($(printf "%'d" "$mem_total_bytes") bytes)"
    echo "  Libre:  $(numfmt --to=iec "$mem_free_bytes")  ($(printf "%'d" "$mem_free_bytes") bytes)"
    echo "  Usado:  $(numfmt --to=iec "$mem_used_bytes")  ($(printf "%'d" "$mem_used_bytes") bytes)  ($mem_used_pct%)"
    echo

    echo " SWAP"
    echo "  Total:  $(numfmt --to=iec "$swap_total_bytes")  ($(printf "%'d" "$swap_total_bytes") bytes)"
    echo "  Libre:  $(numfmt --to=iec "$swap_free_bytes")  ($(printf "%'d" "$swap_free_bytes") bytes)"
    echo "  Usado:  $(numfmt --to=iec "$swap_used_bytes")  ($(printf "%'d" "$swap_used_bytes") bytes)  ($swap_used_pct%)"
    echo

    echo "----------------------------------------------"
    echo
}

option_3() {
    echo "=============================================="
    echo " [PENDIENTE] 10 ARCHIVOS MÁS GRANDES"
    echo "=============================================="
    echo
    echo " Esta funcionalidad será implementada por"
    echo " el compañero encargado de la Opción 3."
    echo
    echo " Debe:"
    echo "   1. Pedir un punto de montaje al usuario"
    echo "   2. Validar que existe y es un directorio"
    echo "   3. Buscar recursivamente los 10 archivos"
    echo "      más grandes con 'find' y 'du'"
    echo "   4. Mostrar nombre, tamaño y trayectoria"
    echo "      completa"
    echo
    return 0
}

option_5() {
    echo "=============================================="
    echo " [PENDIENTE] BACKUP A USB CON CATÁLOGO CSV"
    echo "=============================================="
    echo
    echo " Esta funcionalidad será implementada por"
    echo " el compañero encargado de la Opción 5."
    echo
    echo " Debe:"
    echo "   1. Detectar USB conectados con lsblk"
    echo "   2. Si hay 1 USB, usarlo automáticamente"
    echo "   3. Si hay varios, mostrar menú para elegir"
    echo "   4. Si no hay USB, mostrar error"
    echo "   5. Pedir directorio origen a respaldar"
    echo "   6. Copiar archivos con cp -r"
    echo "   7. Generar catálogo CSV con nombres y"
    echo "      fecha de última modificación"
    echo
    return 0
}

main() {
    local opcion

    while true; do
        show_menu
        read -r -p " Seleccione una opción [0-5]: " opcion
        echo

        case "$opcion" in
            1) option_1 ;;
            2) option_2 ;;
            3) option_3 ;;
            4) option_4 ;;
            5) option_5 ;;
            0)
                echo "Saliendo..."
                exit 0
                ;;
            *)
                echo "Opción inválida. Intente de nuevo."
                echo
                ;;
        esac

        read -r -p "Presione Enter para continuar..."
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

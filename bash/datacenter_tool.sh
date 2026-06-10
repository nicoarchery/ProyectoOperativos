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
    echo " 10 ARCHIVOS MÁS GRANDES"
    echo "=============================================="

    local target
    read -r -p "Ingrese el punto de montaje o directorio a analizar: " target

    if [[ -z "$target" ]]; then
        echo "Error: debe ingresar una ruta." >&2
        echo
        return 1
    fi

    if [[ ! -d "$target" ]]; then
        echo "Error: '$target' no existe o no es un directorio." >&2
        echo
        return 1
    fi

    target=$(realpath -m "$target" 2>/dev/null || printf "%s" "$target")

    echo
    echo "Buscando archivos en: $target"
    echo "Esto puede tardar si el filesystem contiene muchos archivos."
    echo

    printf "%-6s %-18s %s\n" "No." "TAMAÑO (bytes)" "RUTA COMPLETA"
    echo "----------------------------------------------"

    local count=0
    while IFS=$'\t' read -r -d '' size path; do
        count=$((count + 1))
        printf "%-6d %'18d %s\n" "$count" "$size" "$path"
    done < <(find "$target" -xdev -type f -printf '%s\t%p\0' 2>/dev/null | sort -z -nr | head -z -n 10)

    if [[ "$count" -eq 0 ]]; then
        echo "No se encontraron archivos regulares en la ruta indicada."
    fi

    echo "----------------------------------------------"
    echo
    return 0
}

csv_escape() {
    local value=${1//\"/\"\"}
    printf '"%s"' "$value"
}

lsblk_value() {
    local line=$1
    local key=$2
    local rest=${line#*${key}=\"}

    if [[ "$rest" == "$line" ]]; then
        printf ""
        return
    fi

    printf "%s" "${rest%%\"*}"
}

detect_usb_mounts() {
    local line current_usb_disk=""

    while IFS= read -r line; do
        local NAME TRAN TYPE MOUNTPOINT SIZE
        NAME=$(lsblk_value "$line" "NAME")
        TRAN=$(lsblk_value "$line" "TRAN")
        TYPE=$(lsblk_value "$line" "TYPE")
        MOUNTPOINT=$(lsblk_value "$line" "MOUNTPOINT")
        SIZE=$(lsblk_value "$line" "SIZE")

        if [[ "$TYPE" == "disk" ]]; then
            if [[ "$TRAN" == "usb" ]]; then
                current_usb_disk="$NAME"
            else
                current_usb_disk=""
            fi
        fi

        if [[ -n "$current_usb_disk" && ("$TYPE" == "part" || "$TYPE" == "disk") && -n "$MOUNTPOINT" && "$MOUNTPOINT" == /* ]]; then
            printf "%s\t%s\t%s\n" "$MOUNTPOINT" "$NAME" "$SIZE"
        fi
    done < <(lsblk -pnP -o NAME,TRAN,TYPE,MOUNTPOINT,SIZE 2>/dev/null)
}

select_usb_mount() {
    local usb_entries=()
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] && usb_entries+=("$line")
    done < <(detect_usb_mounts)

    if [[ "${#usb_entries[@]}" -eq 0 ]]; then
        echo "Error: no se encontraron particiones USB montadas." >&2
        echo "Conecte y monte una memoria USB antes de ejecutar el backup." >&2
        return 1
    fi

    if [[ "${#usb_entries[@]}" -eq 1 ]]; then
        IFS=$'\t' read -r SELECTED_USB_MOUNT SELECTED_USB_DEVICE SELECTED_USB_SIZE <<< "${usb_entries[0]}"
        echo "USB detectada automáticamente: $SELECTED_USB_MOUNT ($SELECTED_USB_DEVICE, $SELECTED_USB_SIZE)"
        return 0
    fi

    echo "Memorias USB disponibles:"
    local i mount device size
    for i in "${!usb_entries[@]}"; do
        IFS=$'\t' read -r mount device size <<< "${usb_entries[$i]}"
        printf " %d. %s (%s, %s)\n" "$((i + 1))" "$mount" "$device" "$size"
    done

    local choice
    read -r -p "Seleccione la USB destino [1-${#usb_entries[@]}]: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt "${#usb_entries[@]}" ]]; then
        echo "Error: selección inválida." >&2
        return 1
    fi

    IFS=$'\t' read -r SELECTED_USB_MOUNT SELECTED_USB_DEVICE SELECTED_USB_SIZE <<< "${usb_entries[$((choice - 1))]}"
    return 0
}

generate_backup_catalog() {
    local source_dir=$1
    local catalog_file=$2
    local file rel_path modified

    printf '"archivo","ultima_modificacion"\n' > "$catalog_file"

    while IFS= read -r -d '' file; do
        rel_path=${file#"$source_dir"/}
        modified=$(stat -c '%y' "$file" 2>/dev/null || printf "No disponible")
        csv_escape "$rel_path" >> "$catalog_file"
        printf ',' >> "$catalog_file"
        csv_escape "$modified" >> "$catalog_file"
        printf '\n' >> "$catalog_file"
    done < <(find "$source_dir" -type f -print0 2>/dev/null | sort -z)
}

is_path_inside() {
    local child=$1
    local parent=$2

    [[ "$child" == "$parent" || "$child" == "$parent"/* ]]
}

option_5() {
    echo "=============================================="
    echo " BACKUP A USB CON CATÁLOGO CSV"
    echo "=============================================="

    SELECTED_USB_MOUNT=""
    SELECTED_USB_DEVICE=""
    SELECTED_USB_SIZE=""

    select_usb_mount || {
        echo
        return 1
    }

    echo
    local source_dir
    read -r -p "Ingrese el directorio origen a respaldar: " source_dir

    if [[ -z "$source_dir" ]]; then
        echo "Error: debe ingresar un directorio origen." >&2
        echo
        return 1
    fi

    if [[ ! -d "$source_dir" ]]; then
        echo "Error: '$source_dir' no existe o no es un directorio." >&2
        echo
        return 1
    fi

    if [[ ! -r "$source_dir" ]]; then
        echo "Error: no hay permisos de lectura sobre '$source_dir'." >&2
        echo
        return 1
    fi

    source_dir=$(realpath -m "$source_dir" 2>/dev/null || printf "%s" "$source_dir")
    SELECTED_USB_MOUNT=$(realpath -m "$SELECTED_USB_MOUNT" 2>/dev/null || printf "%s" "$SELECTED_USB_MOUNT")

    if [[ ! -d "$SELECTED_USB_MOUNT" || "$SELECTED_USB_MOUNT" != /* ]]; then
        echo "Error: el montaje USB detectado no es una ruta absoluta válida." >&2
        echo
        return 1
    fi

    if [[ ! -w "$SELECTED_USB_MOUNT" ]]; then
        echo "Error: no hay permisos de escritura sobre la USB '$SELECTED_USB_MOUNT'." >&2
        echo
        return 1
    fi

    if is_path_inside "$SELECTED_USB_MOUNT" "$source_dir"; then
        echo "Error: la USB destino está dentro del directorio origen." >&2
        echo "Eso produciría copias recursivas. Seleccione un origen que no contenga la USB." >&2
        echo
        return 1
    fi

    local base_name timestamp backup_root backup_data_dir catalog_file
    base_name=$(basename "$source_dir")
    timestamp=$(date '+%Y%m%d_%H%M%S')
    backup_root="$SELECTED_USB_MOUNT/backup_${base_name}_${timestamp}"
    backup_data_dir="$backup_root/$base_name"
    catalog_file="$backup_root/catalogo_${base_name}_${timestamp}.csv"

    if ! mkdir -p "$backup_data_dir"; then
        echo "Error: no se pudo crear el directorio de backup en la USB." >&2
        echo
        return 1
    fi

    echo
    echo "Copiando archivos..."
    if ! cp -a "$source_dir"/. "$backup_data_dir"/; then
        echo "Error: falló la copia de archivos." >&2
        echo
        return 1
    fi

    echo "Generando catálogo CSV..."
    if ! generate_backup_catalog "$source_dir" "$catalog_file"; then
        echo "Error: no se pudo generar el catálogo." >&2
        echo
        return 1
    fi

    echo
    echo "Backup completado correctamente."
    echo "USB destino:       $SELECTED_USB_MOUNT ($SELECTED_USB_DEVICE)"
    echo "Directorio backup: $backup_root"
    echo "Archivos copiados: $backup_data_dir"
    echo "Catálogo CSV:      $catalog_file"
    echo
    return 0
}

main() {
    local opcion

    while true; do
        show_menu
        read -r -p " Seleccione una opción [1-5]: " opcion
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

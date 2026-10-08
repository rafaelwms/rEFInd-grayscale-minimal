#!/usr/bin/env bash
# Funções compartilhadas por install.sh, uninstall.sh e dualboot.sh
# Shared helpers for install.sh, uninstall.sh and dualboot.sh

THEME_NAME="rEFInd-grayscale-minimal"
MARK_BEGIN="# BEGIN rEFInd-installer (auto-generated, do not edit)"
MARK_END="# END rEFInd-installer"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

select_language() {
    echo "Select your language / Escolha seu idioma:"
    echo "1) English"
    echo "2) Português (Brasil)"
    read -r -p "Option / Opção (1/2): " lang_opt
    case $lang_opt in
        2) LANG_OPT="pt_br" ;;
        1) LANG_OPT="en" ;;
        *) echo "Invalid option / Opção inválida. Defaulting to English."; LANG_OPT="en" ;;
    esac
}

# Mensagens: m "en text" "pt text"
m() { if [ "${LANG_OPT:-en}" = "pt_br" ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }

# ask "en prompt" "pt prompt" -> retorna 0 se sim
confirm() {
    local p; p=$(m "$1 [y/N] " "$2 [s/N] ")
    read -r -p "$p" ans
    case $ans in y|Y|s|S|yes|sim) return 0 ;; *) return 1 ;; esac
}

# Arquitetura -> sufixo do rEFInd (x64, aa64, ia32)
refind_platform() {
    case "$(uname -m)" in
        aarch64|arm64) echo aa64 ;;
        x86_64)        echo x64 ;;
        i?86)          echo ia32 ;;
        *)             echo unknown ;;
    esac
}

# Há suporte a variáveis EFI (NVRAM)? Alguns firmwares ARM (ex.: Qualcomm) não têm.
has_nvram() {
    [ -d /sys/firmware/efi/efivars ] || return 1
    [ -n "$($SUDO ls /sys/firmware/efi/efivars 2>/dev/null | head -n1)" ]
}

# Localiza o ponto de montagem da ESP
find_esp() {
    local d
    for d in /boot/efi /efi /boot; do
        if findmnt -rn "$d" >/dev/null 2>&1 \
           && [ "$(findmnt -rno FSTYPE "$d")" = "vfat" ]; then
            echo "$d"; return 0
        fi
    done
    return 1
}

esp_device() { findmnt -rno SOURCE "$1"; }

# Diretórios da ESP que contêm um refind.conf (EFI/refind e/ou EFI/BOOT)
find_refind_dirs() {
    local esp="$1" d
    for d in "$esp/EFI/refind" "$esp/EFI/BOOT"; do
        $SUDO test -f "$d/refind.conf" && echo "$d"
    done
}

# O arquivo é um binário do rEFInd? (rEFInd contém a string "rEFInd" em UTF-16/ASCII)
is_refind_binary() {
    $SUDO test -f "$1" && $SUDO grep -aq "rEFInd" "$1"
}

pkg_install() {
    if   command -v apt    >/dev/null 2>&1; then $SUDO apt-get update && $SUDO apt-get install -y refind efibootmgr
    elif command -v pacman >/dev/null 2>&1; then $SUDO pacman -S --noconfirm --needed refind efibootmgr
    elif command -v dnf    >/dev/null 2>&1; then $SUDO dnf install -y refind efibootmgr
    elif command -v zypper >/dev/null 2>&1; then $SUDO zypper install -y refind efibootmgr
    else return 1; fi
}

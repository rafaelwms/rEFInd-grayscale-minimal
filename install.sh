#!/usr/bin/env bash
# rEFInd + Grayscale Minimal theme installer (x86_64 and arm64)

cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

install_refind() {
    echo "================================================"
    m "Installing rEFInd..." "Instalando o rEFInd..."

    PLATFORM=$(refind_platform)
    if [ "$PLATFORM" = unknown ]; then
        m "Unsupported CPU architecture: $(uname -m)" "Arquitetura de CPU não suportada: $(uname -m)"
        return 1
    fi
    if [ ! -d /sys/firmware/efi ]; then
        m "This system was not booted in UEFI mode; rEFInd needs UEFI." \
          "Este sistema não foi iniciado em modo UEFI; o rEFInd precisa de UEFI."
        return 1
    fi

    if ! command -v refind-install >/dev/null 2>&1; then
        if ! pkg_install; then
            m "No supported package manager found. Install rEFInd manually." \
              "Nenhum gerenciador de pacotes suportado. Instale o rEFInd manualmente."
            return 1
        fi
    fi
    if ! command -v refind-install >/dev/null 2>&1; then
        m "refind-install command not found." "Comando refind-install não encontrado."
        return 1
    fi

    ESP=$(find_esp) || {
        m "Could not find the EFI System Partition (looked in /boot/efi, /efi, /boot)." \
          "Não foi possível encontrar a partição EFI (procurei em /boot/efi, /efi, /boot)."
        return 1
    }
    ESP_DEV=$(esp_device "$ESP")
    echo "ESP: $ESP ($ESP_DEV)"

    BOOT_FALLBACK="$ESP/EFI/BOOT/boot$PLATFORM.efi"

    if has_nvram; then
        m "EFI variables available: standard install (NVRAM entry)." \
          "Variáveis EFI disponíveis: instalação padrão (entrada na NVRAM)."
        $SUDO refind-install --yes || return 1
    else
        m "This firmware has NO EFI variable support (common on ARM boards like the Radxa Dragon Q6A)." \
          "Este firmware NÃO tem suporte a variáveis EFI (comum em placas ARM como a Radxa Dragon Q6A)."
        m "rEFInd will be installed as the fallback loader (EFI/BOOT/boot$PLATFORM.efi), the only path the firmware can boot." \
          "O rEFInd será instalado como carregador padrão (EFI/BOOT/boot$PLATFORM.efi), o único caminho que o firmware consegue iniciar."

        # Backup do carregador atual (ex.: systemd-boot/GRUB) antes de sobrescrever
        BKP_DIR="$ESP/EFI/refind-backup"
        if $SUDO test -f "$BOOT_FALLBACK" && ! is_refind_binary "$BOOT_FALLBACK"; then
            $SUDO mkdir -p "$BKP_DIR"
            $SUDO cp -n "$BOOT_FALLBACK" "$BKP_DIR/boot$PLATFORM.efi.orig"
            m "Backup saved: $BKP_DIR/boot$PLATFORM.efi.orig" "Backup salvo: $BKP_DIR/boot$PLATFORM.efi.orig"
        fi
        $SUDO refind-install --usedefault "$ESP_DEV" --yes || return 1

        # Em alguns sistemas o refind-install deixa o binário como refind_$PLATFORM.efi
        # e não o renomeia; sem isso o firmware continua iniciando o carregador antigo.
        local src="$ESP/EFI/BOOT/refind_$PLATFORM.efi"
        if $SUDO test -f "$src" && ! $SUDO cmp -s "$src" "$BOOT_FALLBACK"; then
            $SUDO cp "$src" "$BOOT_FALLBACK" && $SUDO sync
        fi
        if ! $SUDO cmp -s "$src" "$BOOT_FALLBACK"; then
            m "ERROR: $BOOT_FALLBACK is not rEFInd; aborting before reboot." \
              "ERRO: $BOOT_FALLBACK não é o rEFInd; abortando antes de reiniciar."
            return 1
        fi
    fi

    configure_refind_conf
    echo "================================================"
}

# Ajusta refind.conf: use_nvram false (sem NVRAM) e entradas para kernels BLS da ESP
configure_refind_conf() {
    local dir conf
    for dir in $(find_refind_dirs "$ESP"); do
        conf="$dir/refind.conf"
        if ! has_nvram && ! $SUDO grep -q "^use_nvram false" "$conf"; then
            echo "use_nvram false" | $SUDO tee -a "$conf" >/dev/null
        fi
        add_bls_entries "$conf"
    done
}

# Gera stanzas para entradas Boot Loader Spec (/loader/entries/*.conf), usadas por
# systemd-boot, com kernel EFI-stub dentro da ESP. Garante boot direto do Linux.
add_bls_entries() {
    local conf="$1" entries="$ESP/loader/entries" f title linux initrd options block="" partuuid icon
    # Se os kernels estão em /boot (rootfs), o rEFInd os acha sozinho e acompanha
    # atualizações; stanzas fixos ficariam obsoletos e duplicariam o menu.
    local settings="scan_delay 1"
    has_nvram || ! $SUDO test -d "$ESP/EFI/refind" || [ "$(dirname "$conf")" = "$ESP/EFI/refind" ] \
        || settings="$settings
dont_scan_dirs EFI/tools,EFI/refind"
    if compgen -G "/boot/vmlinuz-*" >/dev/null || compgen -G "/boot/Image-*" >/dev/null; then
        remove_marked_block "$conf"
        printf '\n%s\n%s\n%s\n' "$MARK_BEGIN" "$settings" "$MARK_END" | $SUDO tee -a "$conf" >/dev/null
        return 0
    fi
    $SUDO test -d "$entries" || return 0
    partuuid=$(lsblk -no PARTUUID "$ESP_DEV" 2>/dev/null)
    [ -n "$partuuid" ] || return 0

    # Ícone do SO (do tema, se instalado ao lado deste refind.conf; senão o padrão do rEFInd)
    local os_id; os_id=$(. /etc/os-release 2>/dev/null; echo "${ID:-linux}")
    icon="/EFI/refind/icons/os_linux.png"
    if $SUDO test -f "$(dirname "$conf")/themes/$THEME_NAME/icons/os_$os_id.png"; then
        icon="/${conf#"$ESP"/}"; icon="$(dirname "$icon")/themes/$THEME_NAME/icons/os_$os_id.png"
    elif $SUDO test -f "$(dirname "$conf")/icons/os_$os_id.png"; then
        icon="$(dirname "/${conf#"$ESP"/}")/icons/os_$os_id.png"
    fi

    for f in $($SUDO sh -c "ls '$entries'/*.conf 2>/dev/null"); do
        title=$($SUDO sed -n 's/^title[[:space:]]\+//p' "$f" | head -n1)
        linux=$($SUDO sed -n 's/^linux[[:space:]]\+//p' "$f" | head -n1)
        initrd=$($SUDO sed -n 's/^initrd[[:space:]]\+//p' "$f" | head -n1)
        options=$($SUDO sed -n 's/^options[[:space:]]\+//p' "$f" | head -n1)
        [ -n "$linux" ] || continue
        block+="menuentry \"${title:-Linux}\" {
    icon $icon
    volume $partuuid
    loader $linux
    ${initrd:+initrd $initrd}
    options \"$options\"
}
"
    done
    [ -n "$block" ] || return 0
    block="$settings
$block"

    remove_marked_block "$conf"
    # Os stanzas precisam vir antes do include do tema? Não; ordem é irrelevante.
    printf '\n%s\n%s%s\n' "$MARK_BEGIN" "$block" "$MARK_END" | $SUDO tee -a "$conf" >/dev/null
    m "Added boot entries from $entries to $conf" "Entradas de $entries adicionadas em $conf"
}

remove_marked_block() {
    $SUDO sed -i "\|^${MARK_BEGIN}\$|,\|^${MARK_END}\$|d" "$1"
}

install_theme() {
    echo "================================================"
    m "Installing Grayscale Minimal Theme..." "Instalando o Tema Grayscale Minimal..."

    ESP=${ESP:-$(find_esp)} || { m "ESP not found." "ESP não encontrada."; return 1; }
    local dirs; dirs=$(find_refind_dirs "$ESP")
    if [ -z "$dirs" ]; then
        m "rEFInd directory not found. Have you installed rEFInd?" \
          "Diretório do rEFInd não encontrado. Você já instalou o rEFInd?"
        return 1
    fi

    local dir dest include="include themes/$THEME_NAME/theme.conf"
    for dir in $dirs; do
        dest="$dir/themes/$THEME_NAME"
        $SUDO rm -rf "$dest"
        $SUDO mkdir -p "$dest"
        $SUDO cp -r icons selection_big.png selection_small.png theme.conf "$dest/"
        $SUDO cp "$BG_CHOICE" "$dest/background.png"
        $SUDO grep -qxF "$include" "$dir/refind.conf" \
            || echo "$include" | $SUDO tee -a "$dir/refind.conf" >/dev/null
        ESP_DEV=${ESP_DEV:-$(esp_device "$ESP")}
        add_bls_entries "$dir/refind.conf"
        echo "-> $dest"
    done
    echo "================================================"
}

select_background() {
    echo ""
    m "Select the background image:" "Selecione a imagem de fundo:"
    echo "1) Skulls"; echo "2) Fender"; echo "3) Gibson"
    read -r -p "$(m 'Option (1-3): ' 'Opção (1-3): ')" bg_opt
    case $bg_opt in
        1) BG_CHOICE="background.skulls.png" ;;
        2) BG_CHOICE="background.fender.png" ;;
        3) BG_CHOICE="background.gibson.png" ;;
        *) m "Invalid option. Please try again." "Opção inválida. Tente novamente."; select_background ;;
    esac
}

main_menu() {
    while true; do
        echo ""
        m "Welcome to the rEFInd Grayscale Minimal Theme Installer!" "Bem-vindo ao Instalador do Tema rEFInd Grayscale Minimal!"
        echo "------------------------------------------------"
        m "What would you like to install?" "O que você gostaria de instalar?"
        m "1) rEFInd Boot Manager" "1) Gerenciador de Inicialização rEFInd"
        m "2) Grayscale Minimal Theme" "2) Tema Grayscale Minimal"
        m "3) Both (rEFInd + Theme)" "3) Ambos (rEFInd + Tema)"
        m "4) Windows dual-boot helper (disk check/partitioning)" "4) Assistente de dual-boot com Windows (análise/particionamento)"
        m "5) Quit" "5) Sair"
        echo "------------------------------------------------"
        read -r -p "$(m 'Select an option (1-5): ' 'Selecione uma opção (1-5): ')" option
        case $option in
            1) install_refind && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            2) select_background; install_theme && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            3) install_refind && { select_background; install_theme; } \
                 && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            4) LANG_OPT=$LANG_OPT ./dualboot.sh; return ;;
            5) m "Installation aborted." "Instalação cancelada."; exit 0 ;;
            *) m "Invalid option. Please try again." "Opção inválida. Tente novamente." ;;
        esac
    done
}

if [ "${1:-}" = "--entries" ]; then   # regenera só as entradas de boot geradas
    ESP=$(find_esp) || exit 1; ESP_DEV=$(esp_device "$ESP"); LANG_OPT=en
    for d in $(find_refind_dirs "$ESP"); do add_bls_entries "$d/refind.conf"; done
    exit 0
fi

select_language
main_menu

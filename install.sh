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
            $SUDO test -e "$BKP_DIR/boot$PLATFORM.efi.orig" || $SUDO cp "$BOOT_FALLBACK" "$BKP_DIR/boot$PLATFORM.efi.orig"
            m "Backup saved: $BKP_DIR/boot$PLATFORM.efi.orig" "Backup salvo: $BKP_DIR/boot$PLATFORM.efi.orig"
        fi
        m "Note: the refind-install ALERT about 'problems detected' is expected here (no EFI variables to register)." \
          "Nota: o ALERT do refind-install sobre 'problemas detectados' é esperado aqui (não há variáveis EFI para registrar)."
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

    local dir
    for dir in $dirs; do
        copy_theme "$dir" "$BG_CHOICE"
        ESP_DEV=${ESP_DEV:-$(esp_device "$ESP")}
        add_bls_entries "$dir/refind.conf"
        echo "-> $dir/themes/$THEME_NAME"
    done
    echo "================================================"
}

# --- Detecção de instalação anterior e atualização -------------------------------------------
# Retorna 0 se encontrou uma instalação (tema e/ou binário) desatualizada e o usuário aceitou atualizar.
check_existing() {
    ESP=$(find_esp) || return 1
    local dir v found="" outdated="" plat; plat=$(refind_platform)
    for dir in $(find_refind_dirs "$ESP"); do
        v=$(installed_theme_version "$dir")
        [ -n "$v" ] && found="$found\n  $dir: $(m "theme version" "versão do tema") $v"
        [ -n "$v" ] && [ "$v" != "$THEME_VERSION" ] && outdated=1
    done
    [ -z "$found" ] && return 1
    echo ""
    m "Previous installation detected:" "Instalação anterior detectada:"
    printf '%b\n' "$found"
    if [ -z "$outdated" ]; then
        m "The theme is already up to date ($THEME_VERSION). Use option 2 to change background/resolution." \
          "O tema já está atualizado ($THEME_VERSION). Use a opção 2 para trocar fundo/resolução."
        return 1
    fi
    m "A newer version is available: $THEME_VERSION." "Há uma versão mais nova: $THEME_VERSION."
    confirm "Update now (your background choice is kept)?" "Atualizar agora (a escolha de fundo é mantida)?" || return 1
    update_existing
}

# Reaplica o tema reaproveitando a imagem escolhida antes (install.info); se não houver, pergunta.
update_existing() {
    local dir info prev="" d
    for dir in $(find_refind_dirs "$ESP"); do
        info="$dir/themes/$THEME_NAME/install.info"
        d=$($SUDO sed -n 's/^background=//p' "$info" 2>/dev/null | head -n1)
        [ -n "$d" ] && [ -f "$d" ] && { prev="$d"; break; }
    done
    if [ -n "$prev" ]; then
        BG_CHOICE="$prev"; m "Keeping previous background: $BG_CHOICE" "Mantendo o fundo anterior: $BG_CHOICE"
    else
        choose_background || return 1
    fi
    install_theme
}

# Diagnóstico somente leitura (cole a saída ao pedir ajuda).
show_status() {
    LANG_OPT=${LANG_OPT:-en}
    ESP_MOUNT_OPTS=ro    # relatório somente leitura: se precisar montar a ESP, monta ro
    echo "== rEFInd installer status (read-only) =="
    echo "arch: $(uname -m) -> $(refind_platform) | UEFI: $([ -d /sys/firmware/efi ] && echo yes || echo no) | NVRAM: $(has_nvram && echo yes || echo no)"
    echo "installer version: $THEME_VERSION | screen: $(detect_resolution || echo unknown)"
    ESP=$(find_esp) || { echo "ESP: not found (mounted vfat at /boot/efi, /efi or /boot)"; return 1; }
    local dev; dev=$(esp_device "$ESP")
    echo "ESP: $ESP ($dev) | free: $($SUDO df -h --output=avail "$ESP" | tail -n1 | tr -d ' ') of $($SUDO df -h --output=size "$ESP" | tail -n1 | tr -d ' ')"
    local dir plat; plat=$(refind_platform)
    for dir in "$ESP/EFI/BOOT" "$ESP/EFI/refind"; do
        $SUDO test -d "$dir" && echo "$dir: refind.conf=$($SUDO test -f "$dir/refind.conf" && echo yes || echo no) theme=$(installed_theme_version "$dir" | sed 's/^$/none/')"
    done
    is_refind_binary "$ESP/EFI/BOOT/boot$plat.efi" && echo "fallback boot$plat.efi: rEFInd" || echo "fallback boot$plat.efi: NOT rEFInd (or missing)"
    $SUDO test -f "$ESP/EFI/Microsoft/Boot/bootmgfw.efi" && echo "Windows boot manager on this ESP: yes" || echo "Windows boot manager on this ESP: no"
    echo "-- disks --"; lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,LABEL,MOUNTPOINT 2>/dev/null | grep -v loop
    has_nvram && command -v efibootmgr >/dev/null && { echo "-- efibootmgr --"; $SUDO efibootmgr 2>/dev/null; }
}

main_menu() {
    while true; do
        echo ""
        m "Welcome to the rEFInd Grayscale Minimal Theme Installer!" "Bem-vindo ao Instalador do Tema rEFInd Grayscale Minimal!"
        echo "------------------------------------------------"
        m "What would you like to install?" "O que você gostaria de instalar?"
        m "1) rEFInd Boot Manager" "1) Gerenciador de Inicialização rEFInd"
        m "2) Grayscale Minimal Theme (also: change background/resolution later)" "2) Tema Grayscale Minimal (também: trocar fundo/resolução depois)"
        m "3) Both (rEFInd + Theme)" "3) Ambos (rEFInd + Tema)"
        m "4) Windows dual-boot helper (disk check/partitioning)" "4) Assistente de dual-boot com Windows (análise/particionamento)"
        m "5) Portable rEFInd on a USB stick (safe/rescue)" "5) rEFInd portátil em pendrive (seguro/resgate)"
        m "6) Quit" "6) Sair"
        echo "------------------------------------------------"
        read -r -p "$(m 'Select an option (1-6): ' 'Selecione uma opção (1-6): ')" option
        case $option in
            1) install_refind && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            2) choose_background || return; install_theme && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            3) install_refind && { choose_background || return; install_theme; } \
                 && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            4) LANG_OPT=$LANG_OPT ./dualboot.sh; return ;;
            5) LANG_OPT=$LANG_OPT ./portable.sh; return ;;
            6) m "Installation aborted." "Instalação cancelada."; exit 0 ;;
            *) m "Invalid option. Please try again." "Opção inválida. Tente novamente." ;;
        esac
    done
}

if [ "${1:-}" = "--entries" ]; then   # regenera só as entradas de boot geradas
    ESP=$(find_esp) || exit 1; ESP_DEV=$(esp_device "$ESP"); LANG_OPT=en
    for d in $(find_refind_dirs "$ESP"); do add_bls_entries "$d/refind.conf"; done
    exit 0
fi

if [ "${1:-}" = "--background" ]; then   # troca só imagem/resolução do tema já instalado
    select_language
    choose_background && install_theme
    exit $?
fi

if [ "${1:-}" = "--status" ]; then show_status; exit $?; fi

if [ "${1:-}" = "--update" ]; then   # atualiza uma instalação anterior sem passar pelo menu
    select_language
    check_existing || m "Nothing to update." "Nada a atualizar."
    exit 0
fi

select_language
check_existing && exit 0    # instalação anterior encontrada e atualizada
main_menu

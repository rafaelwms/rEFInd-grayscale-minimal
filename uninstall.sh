#!/usr/bin/env bash
# rEFInd + Grayscale Minimal theme uninstaller

cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

uninstall_theme() {
    echo "================================================"
    m "Uninstalling Grayscale Minimal Theme..." "Desinstalando o Tema Grayscale Minimal..."
    ESP=$(find_esp) || { m "ESP not found." "ESP não encontrada."; return 1; }
    local dirs dir include="include themes/$THEME_NAME/theme.conf"
    dirs=$(find_refind_dirs "$ESP")
    if [ -z "$dirs" ]; then
        m "rEFInd directory not found. Nothing to uninstall for the theme." \
          "Diretório do rEFInd não encontrado. Nada a desinstalar para o tema."
        return 1
    fi
    for dir in $dirs; do
        $SUDO rm -rf "$dir/themes/$THEME_NAME"
        $SUDO sed -i "\|^${include}\$|d" "$dir/refind.conf"
    done
    echo "================================================"
}

uninstall_refind() {
    echo "================================================"
    m "Uninstalling rEFInd..." "Desinstalando o rEFInd..."
    ESP=$(find_esp) || { m "ESP not found." "ESP não encontrada."; return 1; }
    local platform; platform=$(refind_platform)
    local fallback="$ESP/EFI/BOOT/boot$platform.efi"
    local backup="$ESP/EFI/refind-backup/boot$platform.efi.orig"

    # Restaura o carregador original se o rEFInd estiver ocupando o caminho padrão
    if is_refind_binary "$fallback"; then
        if $SUDO test -f "$backup"; then
            $SUDO cp "$backup" "$fallback" && m "Original fallback loader restored." "Carregador padrão original restaurado."
            $SUDO rm -rf "$ESP/EFI/refind-backup"
        else
            m "WARNING: rEFInd is the fallback loader and no backup exists." \
              "AVISO: o rEFInd é o carregador padrão e não há backup."
            m "Reinstall your original loader (e.g. 'sudo bootctl install' or 'grub-install') before rebooting." \
              "Reinstale seu carregador original (ex.: 'sudo bootctl install' ou 'grub-install') antes de reiniciar."
            confirm "Remove rEFInd anyway?" "Remover o rEFInd mesmo assim?" || return 1
            $SUDO rm -f "$fallback"
        fi
        # Arquivos do rEFInd soltos em EFI/BOOT
        $SUDO rm -rf "$ESP/EFI/BOOT/refind.conf" "$ESP/EFI/BOOT/refind.conf-sample" "$ESP/EFI/BOOT/refind_$platform.efi" \
                     "$ESP/EFI/BOOT/icons" "$ESP/EFI/BOOT/drivers_$platform" "$ESP/EFI/BOOT/themes" "$ESP/EFI/BOOT/keys"
    fi
    $SUDO rm -rf "$ESP/EFI/refind"

    if has_nvram && command -v efibootmgr >/dev/null 2>&1; then
        local n
        for n in $($SUDO efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\? rEFInd.*/\1/p'); do
            $SUDO efibootmgr -b "$n" -B >/dev/null
        done
    fi

    if   command -v apt    >/dev/null 2>&1; then $SUDO apt-get remove --purge -y refind
    elif command -v pacman >/dev/null 2>&1; then $SUDO pacman -Rs --noconfirm refind
    elif command -v dnf    >/dev/null 2>&1; then $SUDO dnf remove -y refind
    elif command -v zypper >/dev/null 2>&1; then $SUDO zypper remove -y refind
    fi
    echo "================================================"
}

main_menu() {
    while true; do
        echo ""
        m "Welcome to the rEFInd Grayscale Minimal Theme Uninstaller!" "Bem-vindo ao Desinstalador do Tema rEFInd Grayscale Minimal!"
        echo "------------------------------------------------"
        m "What would you like to uninstall?" "O que você gostaria de desinstalar?"
        m "1) rEFInd Boot Manager" "1) Gerenciador de Inicialização rEFInd"
        m "2) Grayscale Minimal Theme" "2) Tema Grayscale Minimal"
        m "3) Both (rEFInd + Theme)" "3) Ambos (rEFInd + Tema)"
        m "4) Quit" "4) Sair"
        echo "------------------------------------------------"
        read -r -p "$(m 'Select an option (1-4): ' 'Selecione uma opção (1-4): ')" option
        case $option in
            1) uninstall_refind; break ;;
            2) uninstall_theme; break ;;
            3) uninstall_theme; uninstall_refind; break ;;
            4) m "Uninstallation aborted." "Desinstalação cancelada."; exit 0 ;;
            *) m "Invalid option. Please try again." "Opção inválida. Tente novamente." ;;
        esac
    done
    m "Uninstallation completed successfully!" "Desinstalação concluída com sucesso!"
}

select_language
main_menu

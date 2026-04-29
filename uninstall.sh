#!/usr/bin/env bash

# Função para selecionar o idioma
select_language() {
    echo "Select your language / Escolha seu idioma:"
    echo "1) English"
    echo "2) Português (Brasil)"
    read -p "Option / Opção (1/2): " lang_opt

    case $lang_opt in
        1)
            LANG_OPT="en"
            ;;
        2)
            LANG_OPT="pt_br"
            ;;
        *)
            echo "Invalid option / Opção inválida. Defaulting to English."
            LANG_OPT="en"
            ;;
    esac
}

# Textos em Inglês
en_strings() {
    MSG_WELCOME="Welcome to the rEFInd Grayscale Minimal Theme Uninstaller!"
    MSG_MENU_TITLE="What would you like to uninstall?"
    MSG_OPT_REFIND="1) rEFInd Boot Manager"
    MSG_OPT_THEME="2) Grayscale Minimal Theme"
    MSG_OPT_BOTH="3) Both (rEFInd + Theme)"
    MSG_OPT_QUIT="4) Quit"
    MSG_PROMPT="Select an option (1-4): "
    MSG_UNINSTALL_REFIND="Uninstalling rEFInd..."
    MSG_UNINSTALL_THEME="Uninstalling Grayscale Minimal Theme..."
    MSG_DONE="Uninstallation completed successfully!"
    MSG_INVALID="Invalid option. Please try again."
    MSG_ABORT="Uninstallation aborted."
    MSG_NO_REFIND_DIR="rEFInd directory not found. Nothing to uninstall for the theme."
    MSG_NO_PKG_MGR="Could not find a supported package manager to uninstall rEFInd. Please uninstall it manually."
    MSG_CLEANING_CONF="Removing theme configuration from refind.conf..."
}

# Textos em Português (Brasil)
pt_br_strings() {
    MSG_WELCOME="Bem-vindo ao Desinstalador do Tema rEFInd Grayscale Minimal!"
    MSG_MENU_TITLE="O que você gostaria de desinstalar?"
    MSG_OPT_REFIND="1) Gerenciador de Inicialização rEFInd"
    MSG_OPT_THEME="2) Tema Grayscale Minimal"
    MSG_OPT_BOTH="3) Ambos (rEFInd + Tema)"
    MSG_OPT_QUIT="4) Sair"
    MSG_PROMPT="Selecione uma opção (1-4): "
    MSG_UNINSTALL_REFIND="Desinstalando o rEFInd..."
    MSG_UNINSTALL_THEME="Desinstalando o Tema Grayscale Minimal..."
    MSG_DONE="Desinstalação concluída com sucesso!"
    MSG_INVALID="Opção inválida. Tente novamente."
    MSG_ABORT="Desinstalação cancelada."
    MSG_NO_REFIND_DIR="Diretório do rEFInd não encontrado. Nada a desinstalar para o tema."
    MSG_NO_PKG_MGR="Não foi possível encontrar um gerenciador de pacotes suportado para desinstalar o rEFInd. Por favor, desinstale manualmente."
    MSG_CLEANING_CONF="Removendo configuração do tema do refind.conf..."
}

# Carregar os textos conforme idioma selecionado
load_strings() {
    if [ "$LANG_OPT" = "pt_br" ]; then
        pt_br_strings
    else
        en_strings
    fi
}

# Função para desinstalar o rEFInd
uninstall_refind() {
    echo "================================================"
    echo "$MSG_UNINSTALL_REFIND"
    
    # Tenta usar o gerenciador de pacotes disponível
    if command -v apt &> /dev/null; then
        sudo apt remove --purge -y refind
    elif command -v pacman &> /dev/null; then
        sudo pacman -Rs --noconfirm refind
    elif command -v dnf &> /dev/null; then
        sudo dnf remove -y refind
    elif command -v zypper &> /dev/null; then
        sudo zypper remove -y refind
    else
        echo "$MSG_NO_PKG_MGR"
    fi
    
    echo "================================================"
}

# Função para desinstalar o tema
uninstall_theme() {
    echo "================================================"
    echo "$MSG_UNINSTALL_THEME"
    
    REFIND_DIR=""
    # Busca o diretório onde o rEFInd está instalado
    if [ -d "/boot/efi/EFI/refind" ]; then
        REFIND_DIR="/boot/efi/EFI/refind"
    elif [ -d "/boot/EFI/refind" ]; then
        REFIND_DIR="/boot/EFI/refind"
    elif [ -d "/efi/EFI/refind" ]; then
        REFIND_DIR="/efi/EFI/refind"
    fi

    if [ -z "$REFIND_DIR" ]; then
        echo "$MSG_NO_REFIND_DIR"
        return 1
    fi

    THEMES_DIR="$REFIND_DIR/themes/rEFInd-grayscale-minimal"
    
    # Remove a pasta do tema
    if [ -d "$THEMES_DIR" ]; then
        sudo rm -rf "$THEMES_DIR"
    fi
    
    # Remove a configuração do tema no refind.conf
    CONF_FILE="$REFIND_DIR/refind.conf"
    INCLUDE_LINE="include themes/rEFInd-grayscale-minimal/theme.conf"
    
    if [ -f "$CONF_FILE" ]; then
        echo "$MSG_CLEANING_CONF"
        # Remove a linha de include caso exista
        if grep -q "$INCLUDE_LINE" "$CONF_FILE"; then
            # Usando sed para apagar a linha específica
            sudo sed -i "\|${INCLUDE_LINE}|d" "$CONF_FILE"
        fi
    fi
    echo "================================================"
}

# Menu principal
main_menu() {
    echo ""
    echo "$MSG_WELCOME"
    echo "------------------------------------------------"
    echo "$MSG_MENU_TITLE"
    echo "$MSG_OPT_REFIND"
    echo "$MSG_OPT_THEME"
    echo "$MSG_OPT_BOTH"
    echo "$MSG_OPT_QUIT"
    echo "------------------------------------------------"
    read -p "$MSG_PROMPT" option

    case $option in
        1)
            uninstall_refind
            echo "$MSG_DONE"
            ;;
        2)
            uninstall_theme
            echo "$MSG_DONE"
            ;;
        3)
            uninstall_theme
            uninstall_refind
            echo "$MSG_DONE"
            ;;
        4)
            echo "$MSG_ABORT"
            exit 0
            ;;
        *)
            echo "$MSG_INVALID"
            main_menu
            ;;
    esac
}

# Início da execução
# Garante que o script está sendo rodado a partir do seu diretório atual
cd "$(dirname "$0")" || exit

select_language
load_strings
main_menu

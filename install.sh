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
    MSG_WELCOME="Welcome to the rEFInd Grayscale Minimal Theme Installer!"
    MSG_MENU_TITLE="What would you like to install?"
    MSG_OPT_REFIND="1) rEFInd Boot Manager"
    MSG_OPT_THEME="2) Grayscale Minimal Theme"
    MSG_OPT_BOTH="3) Both (rEFInd + Theme)"
    MSG_OPT_QUIT="4) Quit"
    MSG_PROMPT="Select an option (1-4): "
    MSG_INSTALL_REFIND="Installing rEFInd..."
    MSG_INSTALL_THEME="Installing Grayscale Minimal Theme..."
    MSG_DONE="Installation completed successfully!"
    MSG_INVALID="Invalid option. Please try again."
    MSG_ABORT="Installation aborted."
    MSG_NO_REFIND_DIR="rEFInd directory not found. Have you installed rEFInd?"
    MSG_NO_PKG_MGR="Could not find a supported package manager to install rEFInd. Please install it manually."
    MSG_REFIND_CMD_NOT_FOUND="refind-install command not found."
    MSG_NO_CONF_FILE="Warning: refind.conf not found in"
    MSG_BG_TITLE="Select the background image:"
    MSG_OPT_SKULLS="1) Skulls"
    MSG_OPT_FENDER="2) Fender"
    MSG_OPT_GIBSON="3) Gibson"
    MSG_BG_PROMPT="Option (1-3): "
}

# Textos em Português (Brasil)
pt_br_strings() {
    MSG_WELCOME="Bem-vindo ao Instalador do Tema rEFInd Grayscale Minimal!"
    MSG_MENU_TITLE="O que você gostaria de instalar?"
    MSG_OPT_REFIND="1) Gerenciador de Inicialização rEFInd"
    MSG_OPT_THEME="2) Tema Grayscale Minimal"
    MSG_OPT_BOTH="3) Ambos (rEFInd + Tema)"
    MSG_OPT_QUIT="4) Sair"
    MSG_PROMPT="Selecione uma opção (1-4): "
    MSG_INSTALL_REFIND="Instalando o rEFInd..."
    MSG_INSTALL_THEME="Instalando o Tema Grayscale Minimal..."
    MSG_DONE="Instalação concluída com sucesso!"
    MSG_INVALID="Opção inválida. Tente novamente."
    MSG_ABORT="Instalação cancelada."
    MSG_NO_REFIND_DIR="Diretório do rEFInd não encontrado. Você já instalou o rEFInd?"
    MSG_NO_PKG_MGR="Não foi possível encontrar um gerenciador de pacotes suportado para instalar o rEFInd. Por favor, instale manualmente."
    MSG_REFIND_CMD_NOT_FOUND="Comando refind-install não encontrado."
    MSG_NO_CONF_FILE="Aviso: refind.conf não encontrado em"
    MSG_BG_TITLE="Selecione a imagem de fundo:"
    MSG_OPT_SKULLS="1) Caveiras (Skulls)"
    MSG_OPT_FENDER="2) Fender"
    MSG_OPT_GIBSON="3) Gibson"
    MSG_BG_PROMPT="Opção (1-3): "
}

# Carregar os textos conforme idioma selecionado
load_strings() {
    if [ "$LANG_OPT" = "pt_br" ]; then
        pt_br_strings
    else
        en_strings
    fi
}

# Função para selecionar a imagem de fundo
select_background() {
    echo ""
    echo "$MSG_BG_TITLE"
    echo "$MSG_OPT_SKULLS"
    echo "$MSG_OPT_FENDER"
    echo "$MSG_OPT_GIBSON"
    read -p "$MSG_BG_PROMPT" bg_opt

    case $bg_opt in
        1)
            BG_CHOICE="background.skulls.png"
            ;;
        2)
            BG_CHOICE="background.fender.png"
            ;;
        3)
            BG_CHOICE="background.gibson.png"
            ;;
        *)
            echo "$MSG_INVALID"
            select_background
            ;;
    esac
}

# Função para instalar o rEFInd
install_refind() {
    echo "================================================"
    echo "$MSG_INSTALL_REFIND"
    
    # Tenta usar o gerenciador de pacotes disponível
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y refind
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm refind
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y refind
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y refind
    else
        echo "$MSG_NO_PKG_MGR"
    fi
    
    # Roda o comando refind-install caso esteja disponível
    if command -v refind-install &> /dev/null; then
        sudo refind-install
    else
        echo "$MSG_REFIND_CMD_NOT_FOUND"
    fi
    echo "================================================"
}

# Função para instalar o tema
install_theme() {
    echo "================================================"
    echo "$MSG_INSTALL_THEME"
    
    REFIND_DIR=""
    # Busca o diretório onde o rEFInd está instalado (diferentes pontos de montagem do EFI)
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
    
    # Cria a pasta themes e copia os arquivos
    sudo mkdir -p "$REFIND_DIR/themes"
    sudo cp -r . "$THEMES_DIR"
    
    # Renomeia a imagem de fundo escolhida
    sudo mv "$THEMES_DIR/$BG_CHOICE" "$THEMES_DIR/background.png"
    
    # Remove arquivos desnecessários copiados para a partição EFI
    sudo rm -rf "$THEMES_DIR/.git" "$THEMES_DIR/install.sh" "$THEMES_DIR/uninstall.sh" "$THEMES_DIR"/background.*.png "$THEMES_DIR/README.md"
    
    # Adiciona a configuração do tema no refind.conf
    CONF_FILE="$REFIND_DIR/refind.conf"
    INCLUDE_LINE="include themes/rEFInd-grayscale-minimal/theme.conf"
    
    if [ -f "$CONF_FILE" ]; then
        # Adiciona a linha de include caso não exista
        if ! grep -q "$INCLUDE_LINE" "$CONF_FILE"; then
            echo "$INCLUDE_LINE" | sudo tee -a "$CONF_FILE" > /dev/null
        fi
    else
        echo "$MSG_NO_CONF_FILE $REFIND_DIR"
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
            install_refind
            echo "$MSG_DONE"
            ;;
        2)
            select_background
            install_theme
            echo "$MSG_DONE"
            ;;
        3)
            install_refind
            select_background
            install_theme
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

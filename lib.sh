#!/usr/bin/env bash
# Funções compartilhadas por install.sh, uninstall.sh e dualboot.sh
# Shared helpers for install.sh, uninstall.sh and dualboot.sh

THEME_NAME="rEFInd-grayscale-minimal"
THEME_VERSION=$(cat "$(dirname "${BASH_SOURCE[0]}")/VERSION" 2>/dev/null || echo 0)
MARK_BEGIN="# BEGIN rEFInd-installer (auto-generated, do not edit)"
MARK_END="# END rEFInd-installer"
MARK_WIN_BEGIN="# BEGIN rEFInd-installer-windows (auto-generated, do not edit)"
MARK_WIN_END="# END rEFInd-installer-windows"

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

# Localiza a ESP. Ordem: REFIND_ESP (override) -> vfat montado em /boot/efi, /efi, /boot ->
# partição de tipo GPT "EFI System" montada temporariamente em $ESP_TMP (comum quando a ESP
# não está no fstab). A montagem temporária é desfeita ao sair do script.
ESP_TMP=/run/refind-installer-esp
ESP_GUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b

_esp_cleanup() { findmnt -rn "$ESP_TMP" >/dev/null 2>&1 && $SUDO umount "$ESP_TMP" 2>/dev/null; }
trap _esp_cleanup EXIT

find_esp() {
    local d
    if [ -n "${REFIND_ESP:-}" ] && findmnt -rn "$REFIND_ESP" >/dev/null 2>&1; then echo "$REFIND_ESP"; return 0; fi
    for d in /boot/efi /efi /boot; do
        if findmnt -rn "$d" >/dev/null 2>&1 && [ "$(findmnt -rno FSTYPE "$d")" = "vfat" ]; then
            echo "$d"; return 0
        fi
    done
    findmnt -rn "$ESP_TMP" >/dev/null 2>&1 && { echo "$ESP_TMP"; return 0; }

    # ESP não montada: procura pelo tipo GPT; prefere a que está no mesmo disco da raiz
    local cands root_disk dev=""
    mapfile -t cands < <(lsblk -rnpo NAME,PARTTYPE,FSTYPE | awk -v g="$ESP_GUID" 'tolower($2)==g && $3=="vfat"{print $1}')
    [ "${#cands[@]}" -gt 0 ] || return 1
    root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1)
    for d in "${cands[@]}"; do
        [ "$(lsblk -no PKNAME "$d" 2>/dev/null | head -n1)" = "$root_disk" ] && { dev="$d"; break; }
    done
    [ -z "$dev" ] && [ "${#cands[@]}" -eq 1 ] && dev="${cands[0]}"
    if [ -z "$dev" ]; then
        m "Several EFI partitions found (${cands[*]}). Mount the right one and run: REFIND_ESP=/mount/point $0" \
          "Várias partições EFI encontradas (${cands[*]}). Monte a correta e rode: REFIND_ESP=/ponto/de/montagem $0" >&2
        return 1
    fi
    m "EFI partition $dev is not mounted; mounting it temporarily at $ESP_TMP." \
      "A partição EFI $dev não está montada; montando temporariamente em $ESP_TMP." >&2
    $SUDO mkdir -p "$ESP_TMP" && $SUDO mount -t vfat -o "${ESP_MOUNT_OPTS:-rw}" "$dev" "$ESP_TMP" || return 1
    echo "$ESP_TMP"
}

esp_device() { findmnt -rno SOURCE "$1"; }

# Diretórios da ESP que contêm um refind.conf (EFI/refind, EFI/BOOT e/ou EFI/Microsoft/Boot,
# este último quando o rEFInd ocupa o nome bootmgfw.efi: ver install.sh --windows-loader)
find_refind_dirs() {
    local esp="$1" d
    for d in "$esp/EFI/refind" "$esp/EFI/BOOT" "$esp/EFI/Microsoft/Boot"; do
        $SUDO test -f "$d/refind.conf" && echo "$d"
    done
}

# O arquivo é um binário do rEFInd? Binários UEFI guardam texto em UTF-16 (r\0E\0F\0I\0n\0d\0);
# procurar "rEFInd" em ASCII não acha nada.
is_refind_binary() {
    $SUDO test -f "$1" && $SUDO grep -aqP 'r\x00E\x00F\x00I\x00n\x00d\x00' "$1"
}

pkg_install() {
    if   command -v apt    >/dev/null 2>&1; then
        # O pacote pergunta (debconf) se deve rodar o refind-install sozinho; nós controlamos a instalação
        # (backup do carregador, cópia verificada), então pré-respondemos "não" e evitamos o diálogo.
        echo "refind refind/install_to_esp boolean false" | $SUDO debconf-set-selections 2>/dev/null
        $SUDO apt-get update && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y refind efibootmgr
    elif command -v pacman >/dev/null 2>&1; then $SUDO pacman -S --noconfirm --needed refind efibootmgr
    elif command -v dnf    >/dev/null 2>&1; then $SUDO dnf install -y refind efibootmgr
    elif command -v zypper >/dev/null 2>&1; then $SUDO zypper install -y refind efibootmgr
    else return 1; fi
}

# Copia o tema para um diretório do rEFInd e ativa o include no refind.conf.
# copy_theme <dir_do_refind> <imagem_de_fundo>
copy_theme() {
    local dir="$1" bg="$2" dest="$1/themes/$THEME_NAME" include="include themes/$THEME_NAME/theme.conf"
    $SUDO rm -rf "$dest"
    $SUDO mkdir -p "$dest"
    $SUDO cp -r icons selection_big.png selection_small.png theme.conf "$dest/"
    $SUDO cp "$bg" "$dest/background.png"
    # Fonte com contorno: o tamanho é em pixels da TELA, então segue o monitor (não o fundo escolhido).
    local sres; sres=$(nearest_resolution "$(detect_resolution)")
    [ -f "fonts/$sres/font.png" ] && $SUDO cp "fonts/$sres/font.png" "$dest/font.png"
    # Marca a versão e a escolha feita, para o instalador detectar e atualizar depois
    echo "$THEME_VERSION" | $SUDO tee "$dest/VERSION" >/dev/null
    printf 'background=%s\nscreen=%s\n' "$bg" "$(detect_resolution)" | $SUDO tee "$dest/install.info" >/dev/null
    $SUDO grep -qxF "$include" "$dir/refind.conf" \
        || echo "$include" | $SUDO tee -a "$dir/refind.conf" >/dev/null
}

# Versão do tema instalada em <dir_do_refind>: número, "legacy" (instalado antes do versionamento) ou vazio.
installed_theme_version() {
    local d="$1/themes/$THEME_NAME"
    $SUDO test -d "$d" || return 0
    if $SUDO test -f "$d/VERSION"; then $SUDO cat "$d/VERSION"; else echo legacy; fi
}

# --- Fundos por resolução (backgrounds/<LxA>/background.<nome>.png) ---
BG_RESOLUTIONS="1280x720 1920x1080 2560x1440 3840x2160"
BG_FALLBACK_RES="1920x1080"

# Resolução do monitor: modo preferido do primeiro conector ligado; senão o framebuffer.
detect_resolution() {
    local c r
    for c in /sys/class/drm/card*-*/; do
        [ "$(cat "${c}status" 2>/dev/null)" = connected ] || continue
        r=$(head -n1 "${c}modes" 2>/dev/null)
        [[ "$r" =~ ^[0-9]+x[0-9]+$ ]] && { echo "$r"; return 0; }
    done
    r=$(tr ',' 'x' < /sys/class/graphics/fb0/virtual_size 2>/dev/null)
    [[ "$r" =~ ^[0-9]+x[0-9]+$ ]] && { echo "$r"; return 0; }
    return 1
}

# Resolução disponível mais próxima (pela largura) de $1; 1920x1080 se $1 for vazio.
nearest_resolution() {
    local want="${1%x*}" best="" bd=999999 r d
    [ -n "$1" ] || { echo "$BG_FALLBACK_RES"; return; }
    for r in $BG_RESOLUTIONS; do
        d=$(( ${r%x*} > want ? ${r%x*} - want : want - ${r%x*} ))
        [ "$d" -lt "$bd" ] && { bd=$d; best=$r; }
    done
    echo "$best"
}

# Pergunta imagem e resolução; ENTER = automático. Define BG_CHOICE (caminho do PNG).
choose_background() {
    local det auto name res i=1 opt rs=($BG_RESOLUTIONS)
    det=$(detect_resolution) || det=""
    auto=$(nearest_resolution "$det")
    echo ""
    if [ -z "$det" ]; then
        m "Could not detect the screen resolution; fallback: $BG_FALLBACK_RES." \
          "Não foi possível detectar a resolução da tela; usando o padrão: $BG_FALLBACK_RES."
    elif [ "$det" = "$auto" ]; then
        m "Detected screen resolution: $det (exact match available)." "Resolução detectada: $det (há imagem exata)."
    else
        m "Detected screen resolution: $det. No exact image; closest: $auto (artifacts are possible)." \
          "Resolução detectada: $det. Sem imagem exata; mais próxima: $auto (podem aparecer artefatos)."
    fi

    m "Select the background image:" "Selecione a imagem de fundo:"
    echo "1) Skulls  2) Fender  3) Gibson"
    read -r -p "$(m 'Option (1-3, ENTER = Skulls): ' 'Opção (1-3, ENTER = Skulls): ')" opt
    case $opt in 2) name=fender ;; 3) name=gibson ;; *) name=skulls ;; esac

    m "Select the resolution:" "Selecione a resolução:"
    for res in "${rs[@]}"; do
        echo "$i) $res$([ "$res" = "$auto" ] && m '  <- automatic' '  <- automático')"; i=$((i+1))
    done
    read -r -p "$(m "Option (1-${#rs[@]}, ENTER = automatic): " "Opção (1-${#rs[@]}, ENTER = automático): ")" opt
    if [[ "$opt" =~ ^[0-9]+$ ]] && [ "$opt" -ge 1 ] && [ "$opt" -le "${#rs[@]}" ]; then res=${rs[$((opt-1))]}; else res=$auto; fi

    BG_CHOICE="backgrounds/$res/background.$name.png"
    [ -f "$BG_CHOICE" ] || { m "Image not found: $BG_CHOICE" "Imagem não encontrada: $BG_CHOICE"; return 1; }
    m "Using: $BG_CHOICE" "Usando: $BG_CHOICE"
}

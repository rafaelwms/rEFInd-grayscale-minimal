#!/usr/bin/env bash
# Funções compartilhadas por install.sh, uninstall.sh e dualboot.sh
# Shared helpers for install.sh, uninstall.sh and dualboot.sh

THEME_NAME="rEFInd-grayscale-minimal"
THEME_VERSION=$(cat "$(dirname "${BASH_SOURCE[0]}")/VERSION" 2>/dev/null || echo 0)
# shellcheck disable=SC2034  # usadas pelos scripts que fazem source deste arquivo
MARK_BEGIN="# BEGIN rEFInd-installer (auto-generated, do not edit)"
# shellcheck disable=SC2034
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

# ask_resolution AUTO: lista as resoluções e imprime a escolhida (ENTER = AUTO). Menu vai para o stderr.
ask_resolution() {
    local auto="$1" i=1 res opt rs
    read -ra rs <<<"$BG_RESOLUTIONS"
    m "Select the resolution:" "Selecione a resolução:" >&2
    for res in "${rs[@]}"; do
        echo "$i) $res$([ "$res" = "$auto" ] && m '  <- automatic' '  <- automático')" >&2; i=$((i+1))
    done
    read -r -p "$(m "Option (1-${#rs[@]}, ENTER = automatic): " "Opção (1-${#rs[@]}, ENTER = automático): ")" opt
    if [[ "$opt" =~ ^[0-9]+$ ]] && [ "$opt" -ge 1 ] && [ "$opt" -le "${#rs[@]}" ]; then echo "${rs[$((opt-1))]}"; else echo "$auto"; fi
}

# ensure_pillow: garante o módulo PIL do Python (usado só para preparar o fundo do usuário)
ensure_pillow() {
    python3 -c 'import PIL' 2>/dev/null && return 0
    m "Preparing your image needs Python's Pillow library." "Preparar a sua imagem exige a biblioteca Pillow do Python."
    confirm "Install it now?" "Instalar agora?" || return 1
    if   command -v apt    >/dev/null 2>&1; then $SUDO apt-get install -y python3-pil
    elif command -v pacman >/dev/null 2>&1; then $SUDO pacman -S --noconfirm python-pillow
    elif command -v dnf    >/dev/null 2>&1; then $SUDO dnf install -y python3-pillow
    elif command -v zypper >/dev/null 2>&1; then $SUDO zypper install -y python3-Pillow
    else m "Install Pillow with your package manager and try again." "Instale o Pillow pelo seu gerenciador de pacotes e tente de novo."; return 1
    fi
    python3 -c 'import PIL' 2>/dev/null
}

# custom_background [ARQUIVO] [RES_AUTOMÁTICA]: prepara uma imagem do usuário como fundo e define BG_CHOICE.
# Recorta para 16:9, ajusta à resolução, tira o alfa, cinza opcional, canais em [4,251]; saída em backgrounds/custom/.
custom_background() {
    local src="${1:-}" auto="${2:-}" res color=""
    if [ -z "$src" ]; then
        read -r -e -p "$(m 'Path of your image (PNG/JPEG/WebP...): ' 'Caminho da sua imagem (PNG/JPEG/WebP...): ')" src
    fi
    src=${src%\"}; src=${src#\"}; src=${src%\'}; src=${src#\'}   # tira aspas coladas do gerenciador de arquivos
    src=${src/#\~/$HOME}
    [ -f "$src" ] || { m "File not found: $src" "Arquivo não encontrado: $src"; return 1; }
    ensure_pillow || return 1
    [ -n "$auto" ] || auto=$(nearest_resolution "$(detect_resolution)")
    res=$(ask_resolution "$auto")
    # padrão = cinza (combina com o tema); só mantém as cores se o usuário pedir
    if confirm "Keep the image colors? (default: convert to grayscale)" "Manter as cores da imagem? (padrão: converter para cinza)"; then color="--color"; fi
    mkdir -p backgrounds/custom
    # shellcheck disable=SC2086  # $color é vazio ou uma única flag
    python3 -I tools/make_background.py "$src" "backgrounds/custom/background.png" "$res" $color || return 1
    echo "$src" > backgrounds/custom/source.txt
    BG_CHOICE="backgrounds/custom/background.png"
    m "Using: $BG_CHOICE" "Usando: $BG_CHOICE"
}

# Pergunta imagem e resolução; ENTER = automático. Define BG_CHOICE (caminho do PNG).
choose_background() {
    local det auto name res opt
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
    echo "1) Skulls  2) Fender  3) Gibson  4) $(m 'My own image' 'Minha própria imagem')"
    read -r -p "$(m 'Option (1-4, ENTER = Skulls): ' 'Opção (1-4, ENTER = Skulls): ')" opt
    case $opt in 2) name=fender ;; 3) name=gibson ;; 4) name=custom ;; *) name=skulls ;; esac
    if [ "$name" = custom ]; then custom_background "" "$auto"; return; fi

    res=$(ask_resolution "$auto")
    BG_CHOICE="backgrounds/$res/background.$name.png"
    [ -f "$BG_CHOICE" ] || { m "Image not found: $BG_CHOICE" "Imagem não encontrada: $BG_CHOICE"; return 1; }
    m "Using: $BG_CHOICE" "Usando: $BG_CHOICE"
}

# --- Menu de boot: sistema padrão, tempo de espera, entradas personalizadas ----------------------
# O estado fica no próprio refind.conf, num bloco com marcadores. As linhas "#@ chave=valor" são
# metadados lidos de volta (para o assistente lembrar o que já foi escolhido); o resto do bloco são
# as diretivas do rEFInd. Várias linhas "dont_scan_dirs" SUBSTITUEM a lista anterior, por isso o bloco
# usa "dont_scan_dirs + ..." (acrescenta à lista que o bloco do modo Windows já definiu).
MARK_MENU_BEGIN="# BEGIN rEFInd-installer-menu (auto-generated, do not edit)"
MARK_MENU_END="# END rEFInd-installer-menu"

menu_reset() {
    MENU_POLICY=last        # last | linux | windows | none | custom:<texto>
    MENU_FALLBACK=vmlinuz   # usado por "last" quando ainda não há última seleção
    MENU_TIMEOUT=20         # segundos; -1 = esperar a escolha
    MENU_MOUSE=off          # on|off (enable_mouse: mouse e dispositivos apontadores)
    MENU_ENTRIES=()         # "Nome|ícone|PARTUUID|/caminho/loader.efi|RÓTULO-DO-VOLUME"
}

# menu_read <refind.conf>: carrega o estado do bloco (ou os padrões, se não houver)
menu_read() {
    local conf="$1" line t
    menu_reset
    if ! $SUDO grep -qxF "$MARK_MENU_BEGIN" "$conf" 2>/dev/null; then
        t=$($SUDO sed -n 's/^timeout[[:space:]]\+//p' "$conf" 2>/dev/null | tail -n1)
        [ -n "$t" ] && MENU_TIMEOUT=$t
        return 0
    fi
    while IFS= read -r line; do
        case $line in
            "#@ policy="*)   MENU_POLICY=${line#"#@ policy="} ;;
            "#@ fallback="*) MENU_FALLBACK=${line#"#@ fallback="} ;;
            "#@ timeout="*)  MENU_TIMEOUT=${line#"#@ timeout="} ;;
            "#@ mouse="*)    MENU_MOUSE=${line#"#@ mouse="} ;;
            "#@ entry="*)    MENU_ENTRIES+=("${line#"#@ entry="}") ;;
        esac
    done < <($SUDO sed -n "\|^${MARK_MENU_BEGIN}\$|,\|^${MARK_MENU_END}\$|p" "$conf")
}

# menu_policy_text: descrição legível do padrão atual
menu_policy_text() {
    case $MENU_POLICY in
        last)     m "last selection (fallback: $MENU_FALLBACK)" "última seleção (reserva: $MENU_FALLBACK)" ;;
        linux)    m "Linux (vmlinuz)" "Linux (vmlinuz)" ;;
        windows)  m "Windows" "Windows" ;;
        none)     m "none: wait for my choice" "nenhum: esperar a minha escolha" ;;
        custom:*) m "entry containing \"${MENU_POLICY#custom:}\"" "entrada que contém \"${MENU_POLICY#custom:}\"" ;;
    esac
}

# menu_write <dir_do_refind>: reescreve o bloco do menu em <dir>/refind.conf. Requer $ESP definido.
menu_write() {
    local dir="$1" conf="$1/refind.conf" rel e name icon puuid loader label iconpath hide=""
    rel="${dir#"$ESP"}"
    # remove o bloco antigo; o bloco do modo Windows não pode mais decidir o padrão/tempo (conflitaria)
    $SUDO sed -i "\|^${MARK_MENU_BEGIN}\$|,\|^${MARK_MENU_END}\$|d" "$conf"
    $SUDO sed -i "\|^${MARK_WIN_BEGIN}\$|,\|^${MARK_WIN_END}\$|{/^default_selection /d;/^timeout /d}" "$conf" 2>/dev/null
    {
        printf '\n%s\n' "$MARK_MENU_BEGIN"
        echo "#@ policy=$MENU_POLICY"; echo "#@ fallback=$MENU_FALLBACK"
        echo "#@ timeout=$MENU_TIMEOUT"; echo "#@ mouse=$MENU_MOUSE"
        for e in "${MENU_ENTRIES[@]}"; do echo "#@ entry=$e"; done
        case $MENU_POLICY in
            none)     echo "timeout -1" ;;
            last)     echo "timeout $MENU_TIMEOUT"; echo "default_selection \"+,$MENU_FALLBACK\"" ;;
            linux)    echo "timeout $MENU_TIMEOUT"; echo "default_selection vmlinuz" ;;
            windows)  echo "timeout $MENU_TIMEOUT"; echo "default_selection bootmgfw" ;;
            custom:*) echo "timeout $MENU_TIMEOUT"; echo "default_selection \"${MENU_POLICY#custom:}\"" ;;
        esac
        [ "$MENU_MOUSE" = on ] && echo "enable_mouse true"
        for e in "${MENU_ENTRIES[@]}"; do
            IFS='|' read -r name icon puuid loader label <<<"$e"
            case $icon in
                custom/*) iconpath="$rel/icons-$icon" ;;                       # EFI/BOOT/icons-custom/x.png
                *)        iconpath="$rel/themes/$THEME_NAME/icons/$icon" ;;
            esac
            printf 'menuentry "%s" {\n    icon %s\n    volume %s\n    loader %s\n}\n' "$name" "$iconpath" "$puuid" "$loader"
            [[ "$label" =~ ^[A-Za-z0-9_.-]+$ ]] && hide="$hide,$label:${loader%/*}"
        done
        [ -n "$hide" ] && echo "dont_scan_dirs + ${hide#,}"   # o "+" SEPARADO = acrescenta à lista
        printf '%s\n' "$MARK_MENU_END"
    } | $SUDO tee -a "$conf" >/dev/null
}

# scan_other_loaders: lista "dispositivo|rótulo|PARTUUID|caminho" dos carregadores de fallback
# (EFI/BOOT/boot<arq>.efi) de OUTRAS partições FAT, ou seja, o que o rEFInd mostra como "Fallback boot loader".
# Ignora a ESP em uso e qualquer carregador que seja o próprio rEFInd.
scan_other_loaders() {
    local plat dev fs label puuid own tmp f rel
    plat=$(refind_platform); own=$(esp_device "$ESP" 2>/dev/null)
    while read -r dev fs label puuid; do
        [ "$fs" = vfat ] || continue
        [ "$dev" = "$own" ] && continue
        tmp=$(mktemp -d) || continue
        if $SUDO mount -o ro,noexec,nosuid,nodev "$dev" "$tmp" 2>/dev/null; then
            for rel in "EFI/BOOT/boot$plat.efi" "EFI/Boot/boot$plat.efi"; do
                f="$tmp/$rel"
                if $SUDO test -f "$f" && ! is_refind_binary "$f"; then
                    echo "$dev|$label|$puuid|/EFI/BOOT/boot$plat.efi"; break
                fi
            done
            $SUDO umount "$tmp"
        fi
        rmdir "$tmp" 2>/dev/null
    done < <(lsblk -rnpo NAME,FSTYPE,LABEL,PARTUUID | awk '{ if (NF==3) print $1, $2, "-", $3; else print }')
}

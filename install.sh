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

# Apaga os screenshots do F10 do rEFInd (screenshot_NNN.bmp na raiz da ESP; ~25 MB cada em 4K).
clean_screenshots() {
    [ -z "${LANG_OPT:-}" ] && select_language
    ESP=$(find_esp) || { m "ESP not found." "ESP não encontrada."; return 1; }
    local files n size
    files=$($SUDO find "$ESP" -maxdepth 1 -type f -name 'screenshot_*.bmp' | sort)
    if [ -z "$files" ]; then
        m "No screenshots found in $ESP." "Nenhum screenshot encontrado em $ESP."; return 0
    fi
    n=$(printf '%s\n' "$files" | wc -l)
    size=$(printf '%s\n' "$files" | xargs -d '\n' $SUDO du -ch | tail -n1 | cut -f1)
    m "Found $n screenshot(s) using $size in $ESP:" "Encontrado(s) $n screenshot(s) usando $size em $ESP:"
    printf '%s\n' "$files" | sed 's#^#  #'
    confirm "Delete them (only these files)?" "Apagar (somente estes arquivos)?" || { m "Nothing deleted." "Nada foi apagado."; return 0; }
    $SUDO find "$ESP" -maxdepth 1 -type f -name 'screenshot_*.bmp' -delete
    sync
    m "Done. Free space on the ESP: $($SUDO df -h --output=avail "$ESP" | tail -n1 | tr -d ' ')" \
      "Pronto. Espaço livre na ESP: $($SUDO df -h --output=avail "$ESP" | tail -n1 | tr -d ' ')"
}

# --- Modo "Windows loader" ----------------------------------------------------------------
# Firmwares sem NVRAM (ou com uma entrada própria "Windows Boot Manager") iniciam
# \EFI\Microsoft\Boot\bootmgfw.efi direto e ignoram o rEFInd em EFI/BOOT. Este modo faz o mesmo que o
# refind-install no modo BIOS: guarda o bootmgfw.efi original em EFI/Microsoft/bootmgfw.efi e instala o
# rEFInd com o nome bootmgfw.efi (com configuração, drivers e tema ao lado). Reversível (uninstall.sh).

remove_block() {   # remove_block <arquivo> <inicio> <fim>
    $SUDO sed -i "\|^${2}\$|,\|^${3}\$|d" "$1"
}

# Escreve o bloco do modo (ocultar o que duplicaria + boot padrão) em um refind.conf.
# NÃO cria uma entrada manual do Windows: o rEFInd já detecta sozinho o carregador original movido para
# EFI/Microsoft/bootmgfw.efi (uma stanza manual aparecia duplicada nos F10 de teste).
write_windows_block() {   # write_windows_block <dir_do_refind> <padrao: linux|windows|none>
    local dir="$1" mode="$2" conf="$1/refind.conf"
    remove_block "$conf" "$MARK_WIN_BEGIN" "$MARK_WIN_END"
    {
        printf '\n%s\n' "$MARK_WIN_BEGIN"
        echo "dont_scan_dirs ESP:/EFI/BOOT,EFI/tools,EFI/refind"
        # O padrão (default_selection) e o tempo de espera são gravados pelo bloco do menu (menu_write),
        # para nunca haver duas linhas decidindo a mesma coisa.
        printf '%s\n' "$MARK_WIN_END"
    } | $SUDO tee -a "$conf" >/dev/null
}

windows_loader() {
    [ -z "${LANG_OPT:-}" ] && select_language
    ESP=$(find_esp) || { m "ESP not found." "ESP não encontrada."; return 1; }
    local plat ms msboot src="" bin="" d f mode opt
    plat=$(refind_platform); ms="$ESP/EFI/Microsoft"; msboot="$ms/Boot"

    $SUDO test -f "$msboot/bootmgfw.efi" || {
        m "No Windows boot manager found in $msboot." "Nenhum gerenciador de boot do Windows em $msboot."; return 1; }
    for d in "$ESP/EFI/BOOT" "$ESP/EFI/refind"; do
        $SUDO test -f "$d/refind.conf" && { src="$d"; break; }
    done
    [ -n "$src" ] || { m "Install rEFInd first (menu option 1)." "Instale o rEFInd primeiro (opção 1 do menu)."; return 1; }
    for f in "$src/boot$plat.efi" "$src/refind_$plat.efi"; do
        is_refind_binary "$f" && { bin="$f"; break; }
    done
    [ -n "$bin" ] || { m "rEFInd binary not found in $src." "Binário do rEFInd não encontrado em $src."; return 1; }

    echo ""
    m "Default OS after the timeout:" "Sistema padrão após o tempo de espera:"
    m "1) Linux (ENTER)" "1) Linux (ENTER)"; m "2) Windows" "2) Windows"; m "3) None: wait for my choice" "3) Nenhum: esperar a minha escolha"
    m "4) Remember the last selection (Linux the first time)" "4) Lembrar a última seleção (Linux na primeira vez)"
    read -r -p "$(m 'Option (1-4): ' 'Opção (1-4): ')" opt
    case $opt in 2) mode=windows ;; 3) mode=none ;; 4) mode=last ;; *) mode=linux ;; esac

    # 1) Guardar o gerenciador original do Windows (só se o rEFInd ainda não o substituiu)
    if is_refind_binary "$msboot/bootmgfw.efi"; then
        m "bootmgfw.efi is already rEFInd: refreshing its files only." "O bootmgfw.efi já é o rEFInd: só atualizo os arquivos dele."
        $SUDO test -f "$ms/bootmgfw.efi" || { m "ERROR: original Windows loader not found at $ms/bootmgfw.efi; aborting." \
            "ERRO: o carregador original do Windows não está em $ms/bootmgfw.efi; abortando."; return 1; }
    else
        if $SUDO test -e "$ms/bootmgfw.efi"; then
            $SUDO cmp -s "$msboot/bootmgfw.efi" "$ms/bootmgfw.efi" || { m "ERROR: $ms/bootmgfw.efi exists and differs; aborting without changes." \
                "ERRO: $ms/bootmgfw.efi já existe e é diferente; abortando sem alterar nada."; return 1; }
        else
            $SUDO cp "$msboot/bootmgfw.efi" "$ms/bootmgfw.efi" && $SUDO sync
        fi
        $SUDO cmp -s "$msboot/bootmgfw.efi" "$ms/bootmgfw.efi" || { m "ERROR: backup of the Windows loader failed; nothing was changed." \
            "ERRO: o backup do carregador do Windows falhou; nada foi alterado."; return 1; }
        m "Original Windows loader saved at EFI/Microsoft/bootmgfw.efi (verified)." "Carregador original do Windows guardado em EFI/Microsoft/bootmgfw.efi (verificado)."
    fi

    # 2) Arquivos do rEFInd ao lado do novo bootmgfw.efi (o rEFInd lê configuração e drivers da própria pasta)
    local item
    for item in refind.conf "drivers_$plat" icons themes; do
        $SUDO test -e "$src/$item" || continue
        $SUDO rm -rf "$msboot/$item"
        $SUDO cp -r "$src/$item" "$msboot/$item"
    done
    $SUDO cp "$bin" "$msboot/bootmgfw.efi" && $SUDO sync
    $SUDO cmp -s "$bin" "$msboot/bootmgfw.efi" || { m "ERROR: copy of rEFInd failed. Restore with: sudo cp $ms/bootmgfw.efi $msboot/bootmgfw.efi" \
        "ERRO: a cópia do rEFInd falhou. Restaure com: sudo cp $ms/bootmgfw.efi $msboot/bootmgfw.efi"; return 1; }
    printf 'rEFInd installer windows-loader mode\ninstalled=%s\n' "$(date +%F_%T)" | $SUDO tee "$msboot/refind-installer.info" >/dev/null

    # 3) Configuração das duas cópias (EFI/BOOT ou EFI/refind, e EFI/Microsoft/Boot)
    ESP_DEV=${ESP_DEV:-$(esp_device "$ESP")}
    for d in "$src" "$msboot"; do write_windows_block "$d" "$mode"; done
    menu_read "$src/refind.conf"; MENU_POLICY=$mode        # linux | windows | none | last
    for d in "$src" "$msboot"; do menu_write "$d"; done

    m "Done. rEFInd now also runs when the firmware starts the Windows boot manager." \
      "Pronto. O rEFInd agora também roda quando o firmware inicia o gerenciador de boot do Windows."
    m "The Windows entry in the menu is the original loader at EFI/Microsoft/bootmgfw.efi (untouched). To undo: ./uninstall.sh." \
      "A entrada do Windows no menu é o carregador original em EFI/Microsoft/bootmgfw.efi (intocado). Para desfazer: ./uninstall.sh."
}

# --- Menu de boot: padrão, tempo de espera, entradas personalizadas, mouse -----------------------
# Aplica o estado atual (MENU_*) a todas as cópias do rEFInd na ESP, com backup do refind.conf.
apply_menu() {
    local d f e name icon
    for d in $(find_refind_dirs "$ESP"); do
        $SUDO test -e "$d/refind.conf.bak-menu" || $SUDO cp "$d/refind.conf" "$d/refind.conf.bak-menu"
        menu_write "$d"
        # garante que os ícones do tema usados pelas entradas já estejam na ESP (o tema pode estar desatualizado)
        for e in "${MENU_ENTRIES[@]}"; do
            IFS='|' read -r name icon _ <<<"$e"
            case $icon in custom/*) ;; *)
                if [ -f "icons/$icon" ] && ! $SUDO test -f "$d/themes/$THEME_NAME/icons/$icon"; then
                    $SUDO mkdir -p "$d/themes/$THEME_NAME/icons" && $SUDO cp "icons/$icon" "$d/themes/$THEME_NAME/icons/$icon"
                fi ;;
            esac
        done
        # ícones próprios escolhidos pelo usuário ficam fora da pasta do tema (que é recriada nas atualizações)
        for f in "${!PENDING_ICONS[@]}"; do
            $SUDO mkdir -p "$d/icons-custom" && $SUDO cp "${PENDING_ICONS[$f]}" "$d/icons-custom/$f"
        done
        echo "-> $d/refind.conf"
    done
}

# Pergunta o ícone de uma entrada. Define CHOSEN_ICON ("os_x.png" do tema, ou "custom/nome.png").
choose_icon() {   # choose_icon <sugestão sem extensão>
    local sugg="$1" names=() f n i=1 opt src base
    for f in icons/os_*.png; do n=${f#icons/}; names+=("${n%.png}"); done
    m "Icon for this entry:" "Ícone desta entrada:"
    for n in "${names[@]}"; do
        printf '  %2d) %-18s' "$i" "${n#os_}"; [ $((i % 4)) -eq 0 ] && echo; i=$((i+1))
    done; echo
    m "   c) use my own PNG file" "   c) usar um arquivo PNG meu"
    read -r -p "$(m "Number, name or c (ENTER = ${sugg#os_}): " "Número, nome ou c (ENTER = ${sugg#os_}): ")" opt
    if [ -z "$opt" ]; then CHOSEN_ICON="$sugg.png"
    elif [[ "$opt" =~ ^[0-9]+$ ]] && [ "$opt" -ge 1 ] && [ "$opt" -le "${#names[@]}" ]; then CHOSEN_ICON="${names[$((opt-1))]}.png"
    elif [ "$opt" = c ] || [ "$opt" = C ]; then
        read -r -p "$(m 'Path to the PNG (ideally 320x320, white on transparent): ' 'Caminho do PNG (ideal 320x320, branco sobre transparente): ')" src
        src=${src/#\~/$HOME}
        if [ -f "$src" ] && head -c 8 "$src" | grep -q 'PNG'; then
            base=$(basename "$src" | tr -c 'A-Za-z0-9._-' '_'); PENDING_ICONS["$base"]="$src"; CHOSEN_ICON="custom/$base"
        else m "Not a PNG file; using the suggestion." "Não é um PNG; usando a sugestão."; CHOSEN_ICON="$sugg.png"; fi
    elif [ -f "icons/os_${opt#os_}.png" ]; then CHOSEN_ICON="os_${opt#os_}.png"
    else m "Unknown icon; using the suggestion." "Ícone desconhecido; usando a sugestão."; CHOSEN_ICON="$sugg.png"; fi
}

add_menu_entry() {
    local found=() line dev label puuid loader i=1 opt name sugg lbl
    m "Looking for other systems (FAT partitions with EFI/BOOT/boot*.efi)..." "Procurando outros sistemas (partições FAT com EFI/BOOT/boot*.efi)..."
    mapfile -t found < <(scan_other_loaders)
    if [ "${#found[@]}" -eq 0 ]; then
        m "None found. (Windows and Linux on the ESP are detected by rEFInd on its own.)" "Nenhum encontrado. (Windows e Linux da própria ESP o rEFInd já detecta sozinho.)"; return 0
    fi
    for line in "${found[@]}"; do
        IFS='|' read -r dev label puuid loader <<<"$line"
        lbl=$(printf '%b' "$label"); [ "$lbl" = "-" ] && lbl=$(m "(no label)" "(sem rótulo)")
        printf '  %d) %s  %s  %s\n' "$i" "$dev" "$lbl" "$loader"; i=$((i+1))
    done
    read -r -p "$(m 'Which one (0 = cancel): ' 'Qual (0 = cancelar): ')" opt
    [[ "$opt" =~ ^[0-9]+$ ]] && [ "$opt" -ge 1 ] && [ "$opt" -le "${#found[@]}" ] || return 0
    IFS='|' read -r dev label puuid loader <<<"${found[$((opt-1))]}"
    label=$(printf '%b' "$label")
    name=$(echo "$label" | sed 's/^./\U&/; s/\(.*\)/\1/' | tr '[:upper:]' '[:lower:]' | sed 's/^./\U&/')
    [ "$label" = "-" ] && name="Sistema"
    read -r -p "$(m "Name in the menu (ENTER = $name): " "Nome no menu (ENTER = $name): ")" opt
    opt=${opt//|/ }; opt=${opt//\"/}; [ -n "$opt" ] && name=$opt
    sugg=os_unknown; case "${label,,}${name,,}" in *recal*|*batocera*|*retro*|*game*|*lakka*|*emul*) sugg=os_gamepad ;; *tails*|*whonix*|*privacy*) sugg=os_tails ;; esac
    choose_icon "$sugg"
    # substitui uma entrada de mesmo nome
    local keep=() e
    for e in "${MENU_ENTRIES[@]}"; do [ "${e%%|*}" = "$name" ] || keep+=("$e"); done
    MENU_ENTRIES=("${keep[@]}" "$name|$CHOSEN_ICON|$puuid|$loader|$label")
    m "Entry added: $name" "Entrada adicionada: $name"
}

boot_menu() {
    [ -z "${LANG_OPT:-}" ] && select_language
    ESP=$(find_esp) || { m "ESP not found." "ESP não encontrada."; return 1; }
    ESP_DEV=$(esp_device "$ESP")
    local dirs first opt n i e name
    dirs=$(find_refind_dirs "$ESP"); first=$(echo "$dirs" | head -n1)
    [ -n "$first" ] || { m "rEFInd not found on the ESP. Install it first." "rEFInd não encontrado na ESP. Instale-o primeiro."; return 1; }
    declare -gA PENDING_ICONS=()
    menu_read "$first/refind.conf"
    while true; do
        echo ""; m "== Boot menu ==" "== Menu de boot =="
        echo "  $(m 'Default      :' 'Padrão       :') $(menu_policy_text)"
        echo "  $(m 'Timeout      :' 'Espera       :') $([ "$MENU_POLICY" = none ] && echo '-' || echo "${MENU_TIMEOUT}s")"
        echo "  $(m 'Mouse/touch  :' 'Mouse/toque  :') $MENU_MOUSE"
        i=1; for e in "${MENU_ENTRIES[@]}"; do IFS='|' read -r name _ <<<"$e"; echo "  $(m 'Custom entry' 'Entrada própria') $i: $name"; i=$((i+1)); done
        echo ""
        m "1) Default system" "1) Sistema padrão"
        m "2) Timeout (seconds)" "2) Tempo de espera (segundos)"
        m "3) Add a custom entry (e.g. Recalbox) with an icon" "3) Adicionar entrada própria (ex.: Recalbox) com ícone"
        m "4) Remove a custom entry" "4) Remover entrada própria"
        m "5) Mouse/touch in the menu (on/off)" "5) Mouse/toque no menu (liga/desliga)"
        m "6) Apply and exit" "6) Aplicar e sair"
        m "0) Exit without applying" "0) Sair sem aplicar"
        read -r -p "$(m 'Option: ' 'Opção: ')" opt
        case $opt in
            1) m "  1) Remember the last selection (recommended)" "  1) Lembrar a última seleção (recomendado)"
               m "  2) Always Linux   3) Always Windows   4) Entry containing a text   5) None: wait for me" "  2) Sempre Linux   3) Sempre Windows   4) Entrada que contém um texto   5) Nenhum: esperar por mim"
               read -r -p "  > " n
               case $n in
                   1) MENU_POLICY=last
                      read -r -p "$(m "   Fallback when nothing was selected yet (ENTER = $MENU_FALLBACK): " "   Reserva se ainda não houver seleção (ENTER = $MENU_FALLBACK): ")" n
                      [ -n "$n" ] && MENU_FALLBACK=${n//\"/} ;;
                   2) MENU_POLICY=linux ;;
                   3) MENU_POLICY=windows ;;
                   4) read -r -p "   $(m 'Text of the entry name: ' 'Texto do nome da entrada: ')" n; [ -n "$n" ] && MENU_POLICY="custom:${n//\"/}" ;;
                   5) MENU_POLICY=none ;;
               esac ;;
            2) read -r -p "$(m 'Seconds (0 = boot at once, -1 = wait): ' 'Segundos (0 = iniciar já, -1 = esperar): ')" n
               if [[ "$n" =~ ^-?[0-9]+$ ]]; then MENU_TIMEOUT=$n; else m "Invalid number." "Número inválido."; fi ;;
            3) add_menu_entry ;;
            4) read -r -p "$(m 'Number of the entry to remove: ' 'Número da entrada a remover: ')" n
               if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#MENU_ENTRIES[@]}" ]; then
                   unset 'MENU_ENTRIES[n-1]'; MENU_ENTRIES=("${MENU_ENTRIES[@]}")
               fi ;;
            5) [ "$MENU_MOUSE" = on ] && MENU_MOUSE=off || MENU_MOUSE=on ;;
            6) apply_menu; m "Done. Takes effect on the next boot." "Pronto. Vale a partir do próximo boot."; return 0 ;;
            0) m "Nothing changed." "Nada foi alterado."; return 0 ;;
        esac
    done
}

# Atalhos sem menu: ./install.sh --default last|linux|windows|none|<texto>   e   --timeout <segundos>
boot_menu_quick() {   # boot_menu_quick default <valor> | timeout <n>
    LANG_OPT=${LANG_OPT:-en}
    ESP=$(find_esp) || { m "ESP not found." "ESP não encontrada."; return 1; }
    ESP_DEV=$(esp_device "$ESP"); declare -gA PENDING_ICONS=()
    local first; first=$(find_refind_dirs "$ESP" | head -n1)
    [ -n "$first" ] || { m "rEFInd not found on the ESP." "rEFInd não encontrado na ESP."; return 1; }
    menu_read "$first/refind.conf"
    case $1 in
        default) case $2 in last|linux|windows|none) MENU_POLICY=$2 ;; "") echo "usage: --default last|linux|windows|none|<text>"; return 1 ;; *) MENU_POLICY="custom:${2//\"/}" ;; esac ;;
        timeout) [[ "$2" =~ ^-?[0-9]+$ ]] || { echo "usage: --timeout <seconds>"; return 1; }; MENU_TIMEOUT=$2 ;;
    esac
    apply_menu
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
        m "6) Boot menu: default system, custom entries (Recalbox...), mouse" "6) Menu de boot: sistema padrão, entradas próprias (Recalbox...), mouse"
        m "7) Quit" "7) Sair"
        echo "------------------------------------------------"
        read -r -p "$(m 'Select an option (1-7): ' 'Selecione uma opção (1-7): ')" option
        case $option in
            1) install_refind && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            2) choose_background || return; install_theme && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            3) install_refind && { choose_background || return; install_theme; } \
                 && m "Installation completed successfully!" "Instalação concluída com sucesso!"; return ;;
            4) LANG_OPT=$LANG_OPT ./dualboot.sh; return ;;
            5) LANG_OPT=$LANG_OPT ./portable.sh; return ;;
            6) boot_menu; return ;;
            7) m "Installation aborted." "Instalação cancelada."; exit 0 ;;
            *) m "Invalid option. Please try again." "Opção inválida. Tente novamente." ;;
        esac
    done
}

if [ "${1:-}" = "--entries" ]; then   # regenera só as entradas de boot geradas
    ESP=$(find_esp) || exit 1; ESP_DEV=$(esp_device "$ESP"); LANG_OPT=en
    for d in $(find_refind_dirs "$ESP"); do add_bls_entries "$d/refind.conf"; done
    exit 0
fi

if [ "${1:-}" = "--custom-background" ]; then   # prepara uma imagem sua e instala como fundo: --custom-background [arquivo]
    select_language
    custom_background "${2:-}" && install_theme
    exit $?
fi
if [ "${1:-}" = "--background" ]; then   # troca só imagem/resolução do tema já instalado
    select_language
    choose_background && install_theme
    exit $?
fi

if [ "${1:-}" = "--status" ]; then show_status; exit $?; fi
if [ "${1:-}" = "--clean-screenshots" ]; then clean_screenshots; exit $?; fi
if [ "${1:-}" = "--windows-loader" ]; then windows_loader; exit $?; fi
if [ "${1:-}" = "--boot-menu" ]; then boot_menu; exit $?; fi
if [ "${1:-}" = "--default" ]; then boot_menu_quick default "${2:-}"; exit $?; fi
if [ "${1:-}" = "--timeout" ]; then boot_menu_quick timeout "${2:-}"; exit $?; fi

if [ "${1:-}" = "--update" ]; then   # atualiza uma instalação anterior sem passar pelo menu
    select_language
    check_existing || m "Nothing to update." "Nada a atualizar."
    exit 0
fi

select_language
check_existing && exit 0    # instalação anterior encontrada e atualizada
main_menu

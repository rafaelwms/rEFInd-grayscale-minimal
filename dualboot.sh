#!/usr/bin/env bash
# Assistente para dividir o SSD entre Ubuntu e Windows 11 (UEFI/GPT).
# Helper to share one SSD between Ubuntu and Windows 11 (UEFI/GPT).
#
# Segurança: por padrão só ANALISA (dry-run). Nenhuma alteração é feita sem
# você digitar o nome do disco para confirmar.

cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh
[ -z "${LANG_OPT:-}" ] && select_language

DISK="${1:-}"

pick_disk() {
    if [ -z "$DISK" ]; then
        local root_src; root_src=$(findmnt -no SOURCE /)
        DISK="/dev/$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1)"
    fi
    [ -b "$DISK" ] || { m "Invalid disk: $DISK" "Disco inválido: $DISK"; exit 1; }
}

analyze() {
    echo "================================================"
    m "Disk analysis: $DISK" "Análise do disco: $DISK"
    $SUDO lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,PARTLABEL,MOUNTPOINT "$DISK"
    echo ""
    local ptable; ptable=$($SUDO blkid -s PTTYPE -o value "$DISK")
    m "Partition table: ${ptable:-none}" "Tabela de partições: ${ptable:-nenhuma}"
    [ "$ptable" = gpt ] || m "WARNING: Windows 11 on UEFI requires GPT." "AVISO: o Windows 11 em UEFI exige GPT."

    FREE_BYTES=$($SUDO parted -sm "$DISK" unit B print free 2>/dev/null \
        | awk -F: '$5=="free"{gsub("B","",$4); if ($4+0>max) max=$4+0} END{print max+0}')
    m "Largest unallocated block: $((FREE_BYTES / 1024 / 1024 / 1024)) GiB" \
      "Maior bloco não alocado: $((FREE_BYTES / 1024 / 1024 / 1024)) GiB"

    ESP=$(find_esp) && m "ESP: $ESP ($(esp_device "$ESP")) - will be shared with Windows (>=100 MB free needed)" \
                       "ESP: $ESP ($(esp_device "$ESP")) - será compartilhada com o Windows (>=100 MB livres necessários)"
    $SUDO df -h "${ESP:-/}" | tail -n1
    echo "================================================"
}

# Cria partição NTFS no maior espaço livre
create_windows_partition() {
    local size_gib="$1" start
    command -v sgdisk >/dev/null 2>&1 || $SUDO apt-get install -y gdisk
    command -v mkfs.ntfs >/dev/null 2>&1 || $SUDO apt-get install -y ntfs-3g
    $SUDO sgdisk -n "0:0:+${size_gib}G" -t 0:0700 -c 0:"Windows" "$DISK" || return 1
    $SUDO partprobe "$DISK"; sleep 1
    local part; part=$($SUDO lsblk -nrpo NAME,PARTLABEL "$DISK" | awk '$2=="Windows"{print $1}' | tail -n1)
    $SUDO mkfs.ntfs -f -L Windows "$part"
    m "Created $part (NTFS, ${size_gib} GiB)." "Criada $part (NTFS, ${size_gib} GiB)."
}

# Reduz a raiz ext4 (somente com a partição DESMONTADA, ex.: boot por pendrive/live)
shrink_root() {
    local part="$1" new_gib="$2" num
    if findmnt -rn -S "$part" >/dev/null; then
        m "Partition $part is mounted (you are running from it). ext4 cannot be shrunk online." \
          "A partição $part está montada (você está rodando a partir dela). O ext4 não pode ser reduzido online."
        m "Boot a live system (USB/another disk), then run: sudo ./dualboot.sh $DISK" \
          "Inicie um sistema live (USB/outro disco) e rode: sudo ./dualboot.sh $DISK"
        return 1
    fi
    num=$(cat "/sys/class/block/$(basename "$part")/partition")
    $SUDO e2fsck -f "$part" || return 1
    $SUDO resize2fs "$part" "${new_gib}G" || return 1
    $SUDO parted -s "$DISK" ---pretend-input-tty resizepart "$num" "${new_gib}GiB" <<<"Yes" || return 1
}

windows_instructions() {
    echo "------------------------------------------------"
    m "Next steps for Windows 11 (ARM64):" "Próximos passos para o Windows 11 (ARM64):"
    m "1. Build/download a Windows 11 ARM64 ISO and write it to a USB drive (e.g. with UUP dump + Rufus/WoeUSB)." \
      "1. Gere/baixe uma ISO do Windows 11 ARM64 e grave num pendrive (ex.: UUP dump + Rufus/WoeUSB)."
    m "2. Boot the USB, choose the 'Windows' partition created above, and install there. Do NOT format the ESP." \
      "2. Inicie pelo pendrive, escolha a partição 'Windows' criada acima e instale nela. NÃO formate a ESP."
    m "3. Windows adds EFI/Microsoft to the shared ESP; rEFInd detects it automatically on next boot." \
      "3. O Windows cria EFI/Microsoft na ESP compartilhada; o rEFInd detecta automaticamente no próximo boot."
    m "4. If Windows replaces EFI/BOOT/bootaa64.efi, restore rEFInd with: ./install.sh (option 1)." \
      "4. Se o Windows substituir EFI/BOOT/bootaa64.efi, restaure o rEFInd com: ./install.sh (opção 1)."
    m "NOTE: Windows on the QCS6490 is not officially supported by Radxa/Microsoft; drivers (GPU, Wi-Fi, NVMe quirks) may be missing." \
      "OBS: Windows no QCS6490 não é oficialmente suportado pela Radxa/Microsoft; drivers (GPU, Wi-Fi) podem faltar."
    echo "------------------------------------------------"
}

pick_disk
analyze

GIB_FREE=$((FREE_BYTES / 1024 / 1024 / 1024))
if [ "$GIB_FREE" -ge 64 ]; then
    m "There is enough unallocated space for Windows (>= 64 GiB)." "Há espaço não alocado suficiente para o Windows (>= 64 GiB)."
    read -r -p "$(m 'Size for the Windows partition in GiB (0 = skip): ' 'Tamanho da partição do Windows em GiB (0 = pular): ')" size
    if [ "${size:-0}" -ge 64 ] 2>/dev/null && [ "$size" -le "$GIB_FREE" ]; then
        read -r -p "$(m "Type the disk name ($DISK) to confirm partitioning: " "Digite o nome do disco ($DISK) para confirmar o particionamento: ")" typed
        [ "$typed" = "$DISK" ] && create_windows_partition "$size" || m "Cancelled." "Cancelado."
    fi
else
    m "Not enough unallocated space. You need to shrink the Ubuntu root partition first." \
      "Espaço não alocado insuficiente. É preciso reduzir antes a partição raiz do Ubuntu."
    root_part=$(findmnt -no SOURCE /)
    m "The root ($root_part) is mounted, so this must be done from a live system." \
      "A raiz ($root_part) está montada, então isso precisa ser feito a partir de um sistema live."
    read -r -p "$(m 'Root partition to shrink (empty = skip): ' 'Partição raiz a reduzir (vazio = pular): ')" rp
    if [ -n "$rp" ]; then
        read -r -p "$(m 'New root size in GiB: ' 'Novo tamanho da raiz em GiB: ')" ns
        read -r -p "$(m "Type the disk name ($DISK) to confirm: " "Digite o nome do disco ($DISK) para confirmar: ")" typed
        [ "$typed" = "$DISK" ] && shrink_root "$rp" "$ns" || m "Cancelled." "Cancelado."
    fi
fi
windows_instructions

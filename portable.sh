#!/usr/bin/env bash
# rEFInd portátil: instala o rEFInd (+ tema) num pendrive/SSD USB, sem tocar nos discos internos.
# Portable rEFInd: installs rEFInd (+ theme) on a USB stick, leaving internal disks untouched.
# Serve de "rede de segurança": se o boot interno quebrar, inicie pelo pendrive.

cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh
[ -z "${LANG_OPT:-}" ] && select_language

PLATFORM=$(refind_platform)
SRC=/usr/share/refind/refind
MNT=""
cleanup() { [ -n "$MNT" ] && $SUDO umount "$MNT" 2>/dev/null && rmdir "$MNT" 2>/dev/null; }
trap cleanup EXIT

[ "$PLATFORM" = unknown ] && { m "Unsupported architecture." "Arquitetura não suportada."; exit 1; }

# Arquivos do rEFInd (instala o pacote se precisar; não usa refind-install)
if [ ! -f "$SRC/refind_$PLATFORM.efi" ]; then
    pkg_install || { m "Could not install the refind package." "Não foi possível instalar o pacote refind."; exit 1; }
fi
[ -f "$SRC/refind_$PLATFORM.efi" ] || { m "refind_$PLATFORM.efi not found in $SRC." "refind_$PLATFORM.efi não encontrado em $SRC."; exit 1; }

# --- Escolha do disco USB (nunca o disco do sistema) ---
ROOT_DISK="/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1)"
mapfile -t DISKS < <(lsblk -dnpo NAME,TRAN,SIZE,MODEL | awk -v r="$ROOT_DISK" '$2=="usb" && $1!=r {print}')
if [ "${#DISKS[@]}" -eq 0 ]; then
    m "No USB disk found. Plug in the stick and run again." "Nenhum disco USB encontrado. Conecte o pendrive e rode de novo."
    exit 1
fi
m "USB disks (the system disk is never listed):" "Discos USB (o disco do sistema nunca aparece):"
for i in "${!DISKS[@]}"; do echo "$((i+1))) ${DISKS[$i]}"; done
read -r -p "$(m 'Choose a disk number (0 = cancel): ' 'Escolha o número do disco (0 = cancelar): ')" n
[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#DISKS[@]}" ] || { m "Cancelled." "Cancelado."; exit 0; }
DISK=$(awk '{print $1}' <<<"${DISKS[$((n-1))]}")
[ "$DISK" != "$ROOT_DISK" ] || exit 1

echo ""; $SUDO lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK"; echo ""
m "1) Use an existing FAT partition (keeps the other data)" "1) Usar uma partição FAT existente (mantém os outros dados)"
m "2) ERASE the whole disk and create a dedicated rEFInd partition" "2) APAGAR o disco inteiro e criar uma partição exclusiva do rEFInd"
read -r -p "$(m 'Option (1/2, other = cancel): ' 'Opção (1/2, outra = cancelar): ')" mode

case $mode in
    1)
        mapfile -t PARTS < <(lsblk -lnpo NAME,FSTYPE,SIZE,LABEL "$DISK" | awk '$2=="vfat"{print}')
        [ "${#PARTS[@]}" -gt 0 ] || { m "No FAT partition on $DISK." "Nenhuma partição FAT em $DISK."; exit 1; }
        for i in "${!PARTS[@]}"; do echo "$((i+1))) ${PARTS[$i]}"; done
        read -r -p "$(m 'Partition number: ' 'Número da partição: ')" p
        [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le "${#PARTS[@]}" ] || { m "Cancelled." "Cancelado."; exit 0; }
        PART=$(awk '{print $1}' <<<"${PARTS[$((p-1))]}")
        ;;
    2)
        m "ALL DATA on $DISK will be destroyed." "TODOS OS DADOS de $DISK serão destruídos."
        read -r -p "$(m "Type the device name ($DISK) to confirm: " "Digite o nome do dispositivo ($DISK) para confirmar: ")" typed
        [ "$typed" = "$DISK" ] || { m "Cancelled." "Cancelado."; exit 0; }
        command -v sgdisk    >/dev/null 2>&1 || $SUDO apt-get install -y gdisk
        command -v mkfs.vfat >/dev/null 2>&1 || $SUDO apt-get install -y dosfstools
        $SUDO umount "$DISK"* 2>/dev/null
        $SUDO sgdisk --zap-all "$DISK" >/dev/null || exit 1
        $SUDO sgdisk -n 1:0:0 -t 1:ef00 -c 1:REFIND "$DISK" >/dev/null || exit 1
        $SUDO partprobe "$DISK"; sleep 2
        PART=$($SUDO lsblk -lnpo NAME "$DISK" | sed -n 2p)
        $SUDO mkfs.vfat -F32 -n REFIND "$PART" >/dev/null || exit 1
        ;;
    *) m "Cancelled." "Cancelado."; exit 0 ;;
esac

# --- Monta (reaproveita se já estiver montada) ---
MNT_EXIST=$(findmnt -rno TARGET "$PART" | head -n1)
if [ -n "$MNT_EXIST" ]; then ROOTMNT="$MNT_EXIST"
else MNT=$(mktemp -d) && $SUDO mount "$PART" "$MNT" && ROOTMNT="$MNT" || exit 1; fi

DEST="$ROOTMNT/EFI/BOOT"
BIN="$DEST/boot$PLATFORM.efi"
$SUDO mkdir -p "$DEST"

# Backup de um eventual carregador já existente no pendrive
if [ -f "$BIN" ] && ! is_refind_binary "$BIN"; then
    $SUDO cp -n "$BIN" "$BIN.orig"
    m "Existing loader saved as $(basename "$BIN").orig" "Carregador existente salvo como $(basename "$BIN").orig"
fi

m "Copying rEFInd to $DEST ..." "Copiando o rEFInd para $DEST ..."
$SUDO cp "$SRC/refind_$PLATFORM.efi" "$BIN"
$SUDO mkdir -p "$DEST/drivers_$PLATFORM" "$DEST/icons"
$SUDO cp "$SRC"/drivers_"$PLATFORM"/*.efi "$DEST/drivers_$PLATFORM/"
$SUDO cp -r "$SRC/icons/." "$DEST/icons/"
$SUDO cp "$SRC/refind.conf-sample" "$DEST/refind.conf"
printf '\n%s\nuse_nvram false\nscan_delay 1\nscanfor internal,external,optical,manual\n%s\n' \
    "$MARK_BEGIN" "$MARK_END" | $SUDO tee -a "$DEST/refind.conf" >/dev/null

read -r -p "$(m 'Install the Grayscale Minimal theme too? [y/N] ' 'Instalar também o tema Grayscale Minimal? [s/N] ')" t
case $t in
    y|Y|s|S)
        choose_background || exit 1
        copy_theme "$DEST" "$BG_CHOICE" ;;
esac

$SUDO sync
if $SUDO cmp -s "$SRC/refind_$PLATFORM.efi" "$BIN"; then
    m "Done. Portable rEFInd installed on $PART." "Pronto. rEFInd portátil instalado em $PART."
    m "To use it: plug the stick, open the firmware boot menu (Del on the Radxa Q6A) and choose the USB device." \
      "Para usar: conecte o pendrive, abra o menu de boot do firmware (Del na Radxa Q6A) e escolha o dispositivo USB."
    m "From there, pick your internal Ubuntu/Windows entry." "De lá, escolha a entrada do Ubuntu/Windows interno."
else
    m "ERROR: verification failed ($BIN differs)." "ERRO: a verificação falhou ($BIN diferente)."
    exit 1
fi

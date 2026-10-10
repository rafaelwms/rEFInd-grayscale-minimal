#!/usr/bin/env bash
# Copia um Ubuntu/Linux (ext4) para o espaço livre de um SSD que já tem o Windows (GPT).
# Copies a Linux (ext4) install into the free space of an SSD that already holds Windows (GPT).
# Roda em Linux (ex.: Ubuntu da Radxa ou live). NÃO roda no macOS (sem ext4/rsync -X).
#
# Uso: ./merge-linux.sh [-n|--dry-run]
#   -n  só detecta os discos e mostra o plano; não grava nada.
#
# Só ADICIONA uma partição no espaço livre do destino. Windows, ESP e MSR não são tocados
# (exceto 'sgdisk -e', que move o GPT de backup para o fim do disco; antes disso salva um backup do GPT).
# Depois: pendrive com rEFInd -> iniciar o Ubuntu copiado -> ./install.sh --windows-loader.

cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh
[ -z "${LANG_OPT:-}" ] && select_language

DRY=0
case "${1:-}" in -n|--dry-run) DRY=1 ;; esac

MNT_SRC=/run/merge-linux-src
MNT_DST=/run/merge-linux-dst
SRC_MOUNTED=0; DST_MOUNTED=0
cleanup() {
    sync
    [ "$DST_MOUNTED" = 1 ] && { $SUDO umount -R "$MNT_DST" 2>/dev/null; rmdir "$MNT_DST" 2>/dev/null; }
    [ "$SRC_MOUNTED" = 1 ] && { $SUDO umount "$MNT_SRC" 2>/dev/null; rmdir "$MNT_SRC" 2>/dev/null; }
}
trap cleanup EXIT
die() { m "ERROR: $1" "ERRO: $2" >&2; exit 1; }

# --- Ferramentas ---
need=""
command -v sgdisk >/dev/null    || need="$need gdisk"
command -v rsync >/dev/null     || need="$need rsync"
command -v mkfs.ext4 >/dev/null || need="$need e2fsprogs"
if [ -n "$need" ]; then
    m "Missing tools:$need" "Faltam ferramentas:$need"
    confirm "Install them now?" "Instalar agora?" || exit 1
    $SUDO apt-get update -qq && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $need || die "install failed" "falha na instalação"
fi

ROOT_SRC=$(findmnt -no SOURCE /)
ROOT_DISK="/dev/$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n1)"

list_disks() { lsblk -dnpo NAME,TYPE | awk '$2=="disk" && $1 !~ /zram|loop/ {print $1}' | sort; }
describe()   { lsblk -dnpo NAME,SIZE,TRAN,MODEL,SERIAL "$1"; }

# Detecta o disco recém-plugado (compara antes/depois); se falhar, deixa escolher da lista.
# $1 = texto en, $2 = texto pt (o que plugar). Resultado em $PICKED.
detect_disk() {
    local before after new n i
    before=$(list_disks)
    m "$1" "$2"
    read -r -p "$(m 'Plugged in? Press ENTER to detect... ' 'Plugou? ENTER para detectar... ')" _
    sleep 3; udevadm settle 2>/dev/null
    after=$(list_disks)
    new=$(comm -13 <(echo "$before") <(echo "$after") | grep .)
    if [ -n "$new" ] && [ "$(echo "$new" | wc -l)" -eq 1 ]; then PICKED=$new; return 0; fi
    [ -z "$new" ] && m "No new disk detected." "Nenhum disco novo detectado." || m "More than one new disk." "Mais de um disco novo."
    mapfile -t L < <(echo "$after")
    for i in "${!L[@]}"; do echo "$((i+1))) $(describe "${L[$i]}")"; done
    read -r -p "$(m 'Choose a number (0 = cancel): ' 'Escolha o número (0 = cancelar): ')" n
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#L[@]}" ] || { m "Cancelled." "Cancelado."; exit 0; }
    PICKED=${L[$((n-1))]}
}

# ============ 1. Destino (SSD com Windows) ============
detect_disk "Plug in the DESTINATION SSD (the one that already has Windows)." \
            "Plugue o SSD de DESTINO (o que já tem o Windows)."
DST=$PICKED
[ "$DST" != "$ROOT_DISK" ] || die "the destination cannot be the running system disk" "o destino não pode ser o disco do sistema em execução"
[ "$(lsblk -dno PTTYPE "$DST")" = gpt ] || die "$DST is not GPT" "$DST não é GPT"
lsblk -lno FSTYPE "$DST" | grep -q ntfs || {
    m "WARNING: no NTFS partition on $DST (does it really hold Windows?)." "AVISO: nenhuma partição NTFS em $DST (ele tem mesmo o Windows?)."
    confirm "Continue anyway?" "Continuar mesmo assim?" || exit 0
}
DST_ESP=$(lsblk -lnpo NAME,PARTTYPE "$DST" | awk -v g="$ESP_GUID" 'tolower($2)==g {print $1; exit}')
[ -n "$DST_ESP" ] || die "no EFI System partition on $DST" "sem partição EFI System em $DST"
echo ""; m "Destination:" "Destino:"; $SUDO lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME "$DST"

# ============ 2. Origem (Linux) ============
echo ""
m "Source Linux:" "Linux de origem:"
m "1) The running system (/)" "1) O sistema em execução (/)"
m "2) Another SSD that I will plug in now" "2) Outro SSD que vou plugar agora"
read -r -p "$(m 'Option: ' 'Opção: ')" so
SRC_PART=""
if [ "$so" = 1 ]; then
    SRC=/
    SRC_DISK=$ROOT_DISK
    SRC_PART=$ROOT_SRC
else
    detect_disk "Plug in the SOURCE SSD (the one with Linux)." "Plugue o SSD de ORIGEM (o que tem o Linux)."
    SRC_DISK=$PICKED
    [ "$SRC_DISK" != "$DST" ] || die "source and destination are the same disk" "origem e destino são o mesmo disco"
    # procura a partição ext* com /etc/fstab e /etc/os-release
    $SUDO mkdir -p "$MNT_SRC"
    for p in $(lsblk -lnpo NAME,FSTYPE "$SRC_DISK" | awk '$2 ~ /^ext[234]$/ {print $1}'); do
        mp=$(findmnt -rno TARGET -S "$p" | head -n1)       # o desktop pode ter montado sozinho
        if [ -n "$mp" ]; then
            if [ -f "$mp/etc/fstab" ] && [ -f "$mp/etc/os-release" ]; then SRC_PART=$p; SRC=$mp; break; fi
        elif $SUDO mount -o ro,noload "$p" "$MNT_SRC" 2>/dev/null; then
            if [ -f "$MNT_SRC/etc/fstab" ] && [ -f "$MNT_SRC/etc/os-release" ]; then SRC_PART=$p; SRC=$MNT_SRC; SRC_MOUNTED=1; break; fi
            $SUDO umount "$MNT_SRC"
        fi
    done
    [ -n "$SRC_PART" ] || die "no Linux root (ext4 with /etc/fstab) found on $SRC_DISK" "nenhuma raiz Linux (ext4 com /etc/fstab) em $SRC_DISK"
fi
SRC_NAME=$(. "$SRC/etc/os-release" 2>/dev/null; echo "${PRETTY_NAME:-Linux}")
SRC_USED=$(df -B1 --output=used "$SRC" | tail -n1 | tr -d ' ')
echo ""; m "Source: $SRC_NAME on $SRC_PART ($((SRC_USED/1073741824)) GiB used)" "Origem: $SRC_NAME em $SRC_PART ($((SRC_USED/1073741824)) GiB usados)"
# montagens extras (home separado etc.) ficam de fora do rsync -x
if [ "$SRC" = / ]; then EXTRA=$(findmnt -rn -t ext4,ext3,btrfs,xfs -o TARGET | grep -vx /)
else EXTRA=$($SUDO awk '$1 !~ /^#/ && $2 !~ /^(\/|\/boot\/efi|none|swap)$/ && $3 ~ /^(ext|btrfs|xfs)/ {print $2}' "$SRC/etc/fstab"); fi
[ -n "$EXTRA" ] && { m "WARNING: other mounts are NOT copied (rsync -x): $EXTRA" "AVISO: outras montagens NÃO são copiadas (rsync -x): $EXTRA"; }

# ============ 3. Plano ============
SS=$(cat "/sys/block/${DST#/dev/}/queue/logical_block_size")
GPT_BACKUP="$HOME/gpt-backup-$(lsblk -dno SERIAL "$DST" | tr -c 'A-Za-z0-9\n' _)-$(date +%Y%m%d-%H%M).bin"
START=$($SUDO sgdisk -F "$DST") ; END=$($SUDO sgdisk -E "$DST")
FREE=$(( (END - START + 1) * SS ))
NEED=$(( SRC_USED + SRC_USED / 6 + 3*1073741824 ))   # +~17% +3 GiB de folga
echo ""
m "Largest free block on destination: $((FREE/1073741824)) GiB (needed: ~$((NEED/1073741824)) GiB)" \
  "Maior bloco livre no destino: $((FREE/1073741824)) GiB (necessário: ~$((NEED/1073741824)) GiB)"
[ "$FREE" -ge "$NEED" ] || die "not enough free space (extend the disk or free up the source)" "espaço livre insuficiente"
LABEL=ubuntu-wd; i=2
while $SUDO blkid -L "$LABEL" >/dev/null 2>&1; do LABEL="ubuntu-wd-$i"; i=$((i+1)); done
m "Plan: new ext4 partition labelled '$LABEL' using ALL the free block; GPT backup saved at $GPT_BACKUP" \
  "Plano: nova partição ext4 '$LABEL' usando TODO o bloco livre; backup do GPT em $GPT_BACKUP"
if [ "$DRY" = 1 ]; then m "Dry-run: nothing written." "Dry-run: nada foi gravado."; exit 0; fi

echo ""
m "Type the destination device ($DST) to confirm:" "Para confirmar digite o dispositivo de destino ($DST):"
read -r -p "> " c
[ "$c" = "$DST" ] || { m "Does not match. Nothing changed." "Não confere. Nada foi alterado."; exit 0; }

# ============ 4. Executar ============
$SUDO sgdisk --backup="$GPT_BACKUP" "$DST" || die "GPT backup failed" "backup do GPT falhou"
$SUDO sgdisk -e "$DST" >/dev/null 2>&1                         # GPT de backup no fim do disco
START=$($SUDO sgdisk -F "$DST"); END=$($SUDO sgdisk -E "$DST")
BEFORE_P=$(lsblk -lnpo NAME "$DST" | sort)
$SUDO sgdisk -n "0:${START}:${END}" -t 0:8300 -c "0:$LABEL" "$DST" || die "could not create the partition" "não consegui criar a partição"
$SUDO partprobe "$DST" 2>/dev/null; udevadm settle 2>/dev/null; sleep 2
PART=$(comm -13 <(echo "$BEFORE_P") <(lsblk -lnpo NAME "$DST" | sort) | head -n1)
[ -b "$PART" ] || die "new partition not found" "partição nova não encontrada"
m "Created $PART" "Criada $PART"

# ext4 sem recursos que o driver do rEFInd pode recusar (como na cópia anterior)
$SUDO mkfs.ext4 -F -q -L "$LABEL" -O ^orphan_file,^metadata_csum_seed "$PART" 2>/dev/null ||
$SUDO mkfs.ext4 -F -q -L "$LABEL" -O ^metadata_csum_seed "$PART" 2>/dev/null ||
$SUDO mkfs.ext4 -F -q -L "$LABEL" "$PART" || die "mkfs failed" "mkfs falhou"
NEW_UUID=$($SUDO blkid -s UUID -o value "$PART")
ESP_UUID=$($SUDO blkid -s UUID -o value "$DST_ESP")

for mp in $(lsblk -lnpo MOUNTPOINT "$DST" | grep .); do $SUDO umount "$mp" 2>/dev/null; done   # automontagem do desktop
$SUDO mkdir -p "$MNT_DST"; $SUDO mount "$PART" "$MNT_DST" || die "mount failed" "mount falhou"; DST_MOUNTED=1

m "Copying (can take 15+ min)..." "Copiando (pode levar 15+ min)..."
$SUDO rsync -aAXHx --numeric-ids --info=progress2 \
    --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' \
    --exclude='/mnt/*' --exclude='/media/*' --exclude='/lost+found' --exclude='/swap.img' --exclude='/swapfile' \
    --exclude='/boot/efi/*' \
    "$SRC/" "$MNT_DST/" ; rc=$?
[ $rc -eq 0 ] || [ $rc -eq 24 ] || die "rsync failed (code $rc)" "rsync falhou (código $rc)"   # 24 = arquivo sumiu durante a cópia

# ============ 5. Ajustes no sistema novo ============
F="$MNT_DST/etc/fstab"
$SUDO cp -a "$F" "$F.orig-merge"
$SUDO awk -v root="UUID=$NEW_UUID" -v esp="UUID=$ESP_UUID" '
    /^[[:space:]]*#/ || NF==0 {print; next}
    $2=="/"          {$1=root; print; next}
    $2=="/boot/efi"  {$1=esp; seen=1; print; next}
    $3=="swap" || $1 ~ /^(tmpfs|proc|sysfs|devpts|none)$/ {print; next}
    $1 ~ /^(UUID=|LABEL=|PARTUUID=|PARTLABEL=|\/dev\/)/ {print "#merge-linux: " $0; next}
    {print}
    END {if (!seen) print esp "  /boot/efi  vfat  umask=0077  0  1"}' "$F.orig-merge" | $SUDO tee "$F" >/dev/null

for cf in "$MNT_DST/boot/refind_linux.conf" "$MNT_DST/etc/kernel/cmdline"; do
    [ -f "$cf" ] || continue
    $SUDO cp -a "$cf" "$cf.orig-merge"
    $SUDO sed -i -E "s#root=[^ \"]+#root=UUID=$NEW_UUID#g" "$cf"
done
# kernel-install não deve copiar kernels para a ESP (200–260 MB enche rápido)
$SUDO mkdir -p "$MNT_DST/etc/kernel/install.d"
$SUDO ln -sf /dev/null "$MNT_DST/etc/kernel/install.d/90-loaderentry.install"

# ============ 6. Validar ============
ok=1
chk() { if eval "$2"; then echo "  [OK]   $1"; else echo "  [FAIL] $1"; ok=0; fi; }
m "Validating:" "Validando:"
chk "fstab: root=$NEW_UUID"          "grep -q 'UUID=$NEW_UUID' '$F'"
chk "fstab: /boot/efi=$ESP_UUID"     "grep -q 'UUID=$ESP_UUID' '$F'"
chk "kernel in /boot"                "ls '$MNT_DST'/boot/vmlinuz* >/dev/null 2>&1"
chk "initrd in /boot"                "ls '$MNT_DST'/boot/initrd* >/dev/null 2>&1"
chk "/etc/os-release"                "[ -f '$MNT_DST/etc/os-release' ]"
DIFFS=$($SUDO rsync -aAXHxn --numeric-ids --itemize-changes --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' \
    --exclude='/mnt/*' --exclude='/media/*' --exclude='/lost+found' --exclude='/swap.img' --exclude='/swapfile' --exclude='/boot/efi/*' \
    --exclude='/etc/fstab' --exclude='/etc/kernel/*' --exclude='/boot/refind_linux.conf' --exclude='/var/log/*' --exclude='/var/cache/*' --exclude='/home/*/.cache/*' \
    "$SRC/" "$MNT_DST/" 2>/dev/null | grep -c '^>f')
m "  Files still different (live logs/caches are expected): $DIFFS" "  Arquivos ainda diferentes (logs/caches vivos são esperados): $DIFFS"

# ============ 7. Desmontar ============
sync
$SUDO umount -R "$MNT_DST" && DST_MOUNTED=0
chk "e2fsck on $PART" "$SUDO e2fsck -fn '$PART' >/dev/null 2>&1"
[ "$SRC_MOUNTED" = 1 ] && $SUDO umount "$MNT_SRC" && SRC_MOUNTED=0
$SUDO blockdev --flushbufs "$DST" 2>/dev/null
[ "$SRC" != / ] && $SUDO blockdev --flushbufs "$SRC_DISK" 2>/dev/null
echo ""
if [ "$ok" = 1 ]; then
    m "SUCCESS. $PART (UUID $NEW_UUID) is ready. You can unplug the disks." "SUCESSO. $PART (UUID $NEW_UUID) pronta. Pode desplugar os discos."
    m "Next: boot the rEFInd stick, start this Ubuntu (root=UUID=$NEW_UUID), then run ./install.sh --windows-loader." \
      "Próximo: inicie pelo pendrive com rEFInd, entre neste Ubuntu (root=UUID=$NEW_UUID) e rode ./install.sh --windows-loader."
else
    m "There were FAILURES above. Do not rely on this copy; the Windows partitions were not touched." "Houve FALHAS acima. Não confie nesta cópia; as partições do Windows não foram tocadas."
    exit 1
fi

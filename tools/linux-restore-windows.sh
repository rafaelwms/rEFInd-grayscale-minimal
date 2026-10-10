#!/usr/bin/env bash
# Restaura a imagem do Windows (dd + zstd/gzip) num SSD, a partir de um Linux.
# Equivalente de tools/mac-restore-windows.sh. Só português (script avulso, não usa lib.sh).
#
# Uso: ./linux-restore-windows.sh [imagem]      (padrão: ~/wd-windows-26H2.img.zst)
#
# Fluxo: confere a imagem -> pede para plugar o SSD de destino -> detecta o disco novo
#        -> confirmação digitada -> grava -> compara o hash do disco com o da imagem
#        -> recria o GPT de backup (sgdisk -e) -> desmonta/desliga.
# NÃO apaga nada antes da confirmação. Nunca aceita o disco do sistema em execução.

set -u
IMG="${1:-$HOME/wd-windows-26H2.img.zst}"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

die()  { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[ "$(uname)" = Linux ] || die "Este script é para Linux (no macOS use mac-restore-windows.sh)."
[ -f "$IMG" ] || die "Imagem não encontrada: $IMG"

case "$IMG" in
    *.zst) command -v zstd >/dev/null || die "Falta o zstd (sudo apt install zstd)."; DEC() { zstd -dc "$IMG"; } ;;
    *.gz)  DEC() { gzip -dc "$IMG"; } ;;
    *.img) DEC() { cat "$IMG"; } ;;
    *)     die "Extensão não reconhecida (use .zst, .gz ou .img)." ;;
esac

info "Pedindo sudo uma vez..."
$SUDO -v || die "sudo negado."

# --- 1. Conferir a imagem (a leitura completa já testa a integridade) ---
info "Lendo a imagem (tamanho descomprimido + hash). Leva alguns segundos..."
DEC | tee >(wc -c | tr -d ' ' > "$TMPD/bytes") | sha256sum | cut -d' ' -f1 > "$TMPD/hash"
sleep 1
BYTES=$(cat "$TMPD/bytes"); HASH=$(cat "$TMPD/hash")
[ -n "$BYTES" ] && [ "$BYTES" -gt 0 ] 2>/dev/null || die "Imagem vazia ou corrompida."
echo "    Tamanho descomprimido: $BYTES bytes ($((BYTES / 1048576)) MiB)"
echo "    SHA-256: $HASH"
if [ -f "$IMG.sha256" ]; then
    grep -q "$HASH" "$IMG.sha256" && echo "    Confere com $IMG.sha256" || die "Hash diferente de $IMG.sha256."
fi

# --- 2. Detectar o disco de destino ---
ROOT_DISK="/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1)"
list_disks() { lsblk -dnpo NAME,TYPE | awk '$2=="disk" && $1 !~ /zram|loop/ {print $1}' | sort; }
describe()   { lsblk -dnpo NAME,SIZE,TRAN,MODEL,SERIAL "$1"; }

echo ""
echo "Se o SSD de destino JÁ estiver plugado, desplugue-o agora."
read -r -p "Desplugou (ou nunca esteve plugado)? ENTER para continuar... " _
BEFORE=$(list_disks)
echo "Agora PLUGUE o SSD de destino (aquele que será APAGADO)."
read -r -p "Plugou? ENTER para detectar... " _
sleep 3; udevadm settle 2>/dev/null
AFTER=$(list_disks)
NEW=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep .)

if [ -n "$NEW" ] && [ "$(echo "$NEW" | wc -l)" -eq 1 ]; then
    DISK=$NEW
else
    [ -z "$NEW" ] && echo "Nenhum disco novo detectado." || echo "Mais de um disco novo."
    mapfile -t L < <(echo "$AFTER")
    for i in "${!L[@]}"; do echo "$((i+1))) $(describe "${L[$i]}")"; done
    read -r -p "Escolha o número do destino (0 = cancelar): " n
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#L[@]}" ] || { echo "Cancelado."; exit 0; }
    DISK=${L[$((n-1))]}
fi

# --- 3. Travas de segurança ---
[ -b "$DISK" ] || die "$DISK não é um dispositivo de bloco."
[ "$(lsblk -dno TYPE "$DISK")" = disk ] || die "$DISK não é um disco inteiro."
[ "$DISK" != "$ROOT_DISK" ] || die "$DISK é o disco do sistema em execução. Recusado."
DSIZE=$(lsblk -dbno SIZE "$DISK")
[ "$DSIZE" -ge "$BYTES" ] || die "O disco ($DSIZE bytes) é menor que a imagem ($BYTES bytes)."

echo ""
echo "================ DESTINO ================"
$SUDO lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK"
describe "$DISK"
echo "========================================="
echo "TUDO que existe nesse disco será APAGADO."
read -r -p "Para confirmar, digite o dispositivo ($DISK): " CONF
[ "$CONF" = "$DISK" ] || { echo "Não confere. Nada foi alterado."; exit 0; }

# --- 4. Gravar ---
for mp in $(lsblk -lnpo MOUNTPOINT "$DISK" | grep .); do $SUDO umount "$mp" || die "Não consegui desmontar $mp."; done
BLOCKS=$(( (BYTES + 1048575) / 1048576 ))
info "Gravando $BLOCKS MiB em $DISK ..."
DEC | $SUDO dd of="$DISK" bs=1M iflag=fullblock oflag=direct conv=fsync status=progress || die "dd falhou."
sync

# --- 5. Validar: o hash do que está no disco tem de ser igual ao da imagem ---
info "Validando (relendo o disco)..."
OUT=$($SUDO dd if="$DISK" bs=1M count="$BLOCKS" iflag=direct 2>/dev/null | head -c "$BYTES" | sha256sum | cut -d' ' -f1)
if [ "$OUT" = "$HASH" ]; then
    echo "    OK: hash do disco == hash da imagem."
else
    echo "    FALHOU: disco $OUT != imagem $HASH" >&2
    echo "    Não use este disco. Tente gravar de novo." >&2
    exit 1
fi

# --- 6. GPT de backup no fim do disco (a imagem só levou o GPT primário) ---
if command -v sgdisk >/dev/null; then
    $SUDO sgdisk -e "$DISK" >/dev/null 2>&1 && echo "    GPT de backup recriado (sgdisk -e)." || echo "    sgdisk -e falhou; rode-o manualmente: sudo sgdisk -e $DISK"
else
    echo "    (sgdisk não instalado: 'sudo apt install gdisk' e depois 'sudo sgdisk -e $DISK'. O boot não depende disso.)"
fi
$SUDO partprobe "$DISK" 2>/dev/null

# --- 7. Desmontar e liberar ---
sync
for mp in $(lsblk -lnpo MOUNTPOINT "$DISK" | grep .); do $SUDO umount "$mp" 2>/dev/null; done
$SUDO blockdev --flushbufs "$DISK" 2>/dev/null
command -v udisksctl >/dev/null && $SUDO udisksctl power-off -b "$DISK" >/dev/null 2>&1 && info "Disco desligado. Pode removê-lo."
echo ""
echo "Próximos passos: SSD no slot NVMe da Radxa (sem o WD original junto: mesmo GUID de disco),"
echo "iniciar o Windows e estender o C: no Gerenciamento de Disco."

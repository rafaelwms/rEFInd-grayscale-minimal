#!/bin/bash
# Restaura a imagem do Windows (dd + zstd/gzip) num SSD externo, a partir do macOS.
# Compatível com o bash 3.2 do macOS. Só português (script avulso, não usa lib.sh).
#
# Uso: ./mac-restore-windows.sh [imagem]      (padrão: ~/wd-windows-26H2.img.zst)
#
# Fluxo: confere a imagem -> pede para plugar o SSD de destino -> detecta o disco novo
#        -> confirmação digitada -> grava -> compara o hash do disco com o da imagem -> ejeta.
# NÃO apaga nada antes da confirmação. Só aceita disco externo e nunca o disco do sistema.

set -u
IMG="${1:-$HOME/wd-windows-26H2.img.zst}"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

die()  { echo "ERRO: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[ "$(uname)" = Darwin ] || die "Este script é para macOS."
[ -f "$IMG" ] || die "Imagem não encontrada: $IMG"

case "$IMG" in
    *.zst) command -v zstd >/dev/null || die "Falta o zstd (brew install zstd)."; DEC() { zstd -dc "$IMG"; } ;;
    *.gz)  DEC() { gzip -dc "$IMG"; } ;;
    *.img) DEC() { cat "$IMG"; } ;;
    *)     die "Extensão não reconhecida (use .zst, .gz ou .img)." ;;
esac

info "Pedindo sudo uma vez..."
sudo -v || die "sudo negado."

# --- 1. Conferir a imagem (a leitura completa já testa a integridade) ---
info "Lendo a imagem (tamanho descomprimido + hash). Leva alguns segundos..."
DEC | tee >(wc -c | tr -d ' ' > "$TMPD/bytes") | shasum -a 256 | cut -d' ' -f1 > "$TMPD/hash"
BYTES=$(cat "$TMPD/bytes"); HASH=$(cat "$TMPD/hash")
[ -n "$BYTES" ] && [ "$BYTES" -gt 0 ] 2>/dev/null || die "Imagem vazia ou corrompida."
echo "    Tamanho descomprimido: $BYTES bytes ($((BYTES / 1048576)) MiB)"
echo "    SHA-256: $HASH"
[ -f "$IMG.sha256" ] && { grep -q "$HASH" "$IMG.sha256" && echo "    Confere com $IMG.sha256" || die "Hash diferente de $IMG.sha256."; }

# --- 2. Detectar o disco de destino ---
ext_disks() { diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk/ {print $1}' | sort; }

disk_size()  { diskutil info "$1" | sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p' | head -n1; }
disk_model() { diskutil info "$1" | sed -n 's/.*Device \/ Media Name: *//p' | head -n1; }

describe() { echo "    $1  —  $(disk_model "$1")  —  $(disk_size "$1") bytes"; }

BEFORE=$(ext_disks)
echo ""
echo "Se o SSD de destino JÁ estiver plugado, desplugue-o agora."
read -r -p "Desplugou (ou nunca esteve plugado)? ENTER para continuar... " _
BEFORE=$(ext_disks)
echo "Agora PLUGUE o SSD de destino (aquele que será APAGADO)."
read -r -p "Plugou? ENTER para detectar... " _
sleep 4
AFTER=$(ext_disks)
NEW=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep . )

if [ -z "$NEW" ]; then
    echo "Nenhum disco novo detectado. Discos externos atuais:"
    for d in $AFTER; do describe "$d"; done
    read -r -p "Digite o identificador do destino (ex.: /dev/disk4) ou ENTER para cancelar: " DISK
    [ -n "$DISK" ] || { echo "Cancelado."; exit 0; }
elif [ "$(echo "$NEW" | wc -l | tr -d ' ')" -gt 1 ]; then
    echo "Mais de um disco novo:"
    for d in $NEW; do describe "$d"; done
    read -r -p "Digite o identificador do destino: " DISK
else
    DISK="$NEW"
fi

# --- 3. Travas de segurança ---
case "$DISK" in /dev/disk[0-9]*) ;; *) die "Identificador inválido: $DISK" ;; esac
diskutil info "$DISK" >/dev/null 2>&1 || die "$DISK não existe."
diskutil info "$DISK" | grep -q "Device Location: *External" || die "$DISK não é um disco externo. Recusado."
diskutil info "$DISK" | grep -q "Whole: *Yes" || die "$DISK não é um disco inteiro (é uma partição)."
echo "$AFTER" | grep -qx "$DISK" || die "$DISK não está na lista de discos externos."
DSIZE=$(disk_size "$DISK")
[ -n "$DSIZE" ] || die "Não consegui ler o tamanho de $DISK."
[ "$DSIZE" -ge "$BYTES" ] || die "O disco ($DSIZE bytes) é menor que a imagem ($BYTES bytes)."

echo ""
echo "================ DESTINO ================"
diskutil list "$DISK"
describe "$DISK"
echo "========================================="
echo "TUDO que existe nesse disco será APAGADO (só a região da imagem é gravada,"
echo "mas a tabela de partições antiga deixa de valer)."
read -r -p "Para confirmar, digite o identificador do disco ($DISK): " CONF
[ "$CONF" = "$DISK" ] || { echo "Não confere. Nada foi alterado."; exit 0; }

# --- 4. Gravar ---
RDISK=${DISK/disk/rdisk}
BLOCKS=$(( (BYTES + 1048575) / 1048576 ))
diskutil unmountDisk force "$DISK" >/dev/null || die "Não consegui desmontar $DISK."
info "Gravando $BLOCKS MiB em $RDISK ..."
DEC | sudo dd of="$RDISK" bs=1m status=progress || die "dd falhou."
sync

# --- 5. Validar: o hash do que está no disco tem de ser igual ao da imagem ---
diskutil unmountDisk force "$DISK" >/dev/null 2>&1
info "Validando (relendo o disco)..."
OUT=$(sudo dd if="$RDISK" bs=1m count="$BLOCKS" 2>/dev/null | head -c "$BYTES" | shasum -a 256 | cut -d' ' -f1)
if [ "$OUT" = "$HASH" ]; then
    echo "    OK: hash do disco == hash da imagem."
else
    echo "    FALHOU: disco $OUT != imagem $HASH" >&2
    echo "    Não use este disco. Tente gravar de novo." >&2
    exit 1
fi

# --- 6. GPT de backup (opcional; o macOS costuma negar) ---
if sudo gpt recover "$DISK" >/dev/null 2>&1; then
    echo "    GPT de backup recriado."
else
    echo "    (gpt recover negado pelo macOS — normal. O boot não depende disso;"
    echo "     o merge-linux.sh recria o GPT de backup com 'sgdisk -e'.)"
fi

# --- 7. Ejetar ---
diskutil eject "$DISK" >/dev/null 2>&1 && info "Disco ejetado. Pode removê-lo." || echo "Ejete manualmente pelo Finder."
echo ""
echo "Próximos passos: SSD no slot NVMe da Radxa (sem o WD original junto: mesmo GUID de disco),"
echo "iniciar o Windows e estender o C: no Gerenciamento de Disco."

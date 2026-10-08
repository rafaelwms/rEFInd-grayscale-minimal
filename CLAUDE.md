# CLAUDE.md — rEFInd Grayscale Minimal (arm64 / Radxa Dragon Q6A)

Projeto: instalador do rEFInd + tema grayscale. Meta: funcionar em arm64 (Radxa Dragon Q6A, QCS6490)
e permitir dual-boot Ubuntu + Windows 11. Idioma de trabalho com o usuário: português (BR).
O usuário quer acompanhar cada passo e fará os commits (não commitar; git sem identidade configurada).

## Arquivos
- `lib.sh` — helpers (idioma `m`, `has_nvram`, `find_esp`, `find_refind_dirs`, `is_refind_binary`, `pkg_install`).
- `install.sh` — menu: rEFInd / tema / ambos / assistente dual-boot. `./install.sh --entries` regenera só o bloco gerado do refind.conf.
- `uninstall.sh` — remove tema/rEFInd e restaura o carregador original do backup.
- `dualboot.sh [/dev/disco]` — analisa o disco; cria partição NTFS em espaço livre; guia redução da raiz (só de sistema live).
- `theme.conf`, `icons/`, `background.*.png`, `selection_*.png` — tema.

## Ambiente (Radxa Dragon Q6A)
- Ubuntu 26.04, kernel 7.2.9-edge-qcs6490, aarch64, boot UEFI. SSD NVMe interno 512 GB: p1 config 16M, p2 ESP 1G (/boot/efi), p3 rootfs ext4.
- Kernel/initrd também ficam na ESP (`/<machine-id>/<versão>/linux`, entradas BLS em `/loader/entries`) e em `/boot` (rootfs).
- **O firmware NÃO tem variáveis EFI** (`/sys/firmware/efi/efivars` vazio): `efibootmgr`/NVRAM não funcionam, nem ordem de boot.
  O firmware só inicia `EFI/BOOT/BOOTAA64.EFI`. Ordem de disco: menu do firmware (tecla Del).
- A ESP só é legível com root (`sudo sh -c '...'` para globs; o glob sem sudo falha com "no matches").
- Monitor 4K (3840x2160) via HDMI; o rEFInd roda em 4K nativo.
- O scratchpad (/tmp) é limpo a cada reboot; não guardar nada importante lá.

## Perrengues já resolvidos (não repetir)
1. **rEFInd instalado mas nunca iniciava.** `refind-install` copia para `EFI/refind` mas, sem NVRAM, não registra boot.
   `--usedefault` colocava o binário como `EFI/BOOT/refind_aa64.efi` **sem renomear** para `BOOTAA64.EFI` (que seguia sendo systemd-boot).
   Correção no `install.sh`: backup em `EFI/refind-backup/bootaa64.efi.orig`, cópia manual e verificação com `cmp` (aborta se falhar).
2. **Entradas duplicadas.** O rEFInd acha o kernel de `/boot` sozinho (segue symlink, acompanha updates). Stanzas fixos gerados a partir de
   `/loader/entries` ficam obsoletos após update de kernel. Decisão: só gerar stanzas BLS se o kernel NÃO estiver em `/boot`.
   Bloco gerado fica entre `# BEGIN/END rEFInd-installer` no refind.conf. `EFI/refind` é escondido via `dont_scan_dirs` no `EFI/BOOT/refind.conf` (cópia duplicada do próprio rEFInd).
3. **Pixels coloridos ("raspas") no fundo.** Não estavam nas imagens (conferido: opacas, croma ≤ 11). Vinham da reescala do rEFInd
   (2816x1536 → 4K): valores em áreas quase pretas estouravam para 255 (screenshot via F10 do rEFInd, salvo na ESP como screenshot_NNN.bmp, provou).
   Correção: fundo já em 3840x2160, escala de cinza, canais limitados a [4,251], sem alpha → **zero ruído confirmado pelo usuário**.
4. Windows 11 (SSD do usuário) estava num case USB (`sda`, selo de pendrive no rEFInd); no slot NVMe da Radxa ele já rodou antes. Via USB dá tela preta.
   Sem NVRAM, o firmware tenta o Windows primeiro se estiver ligado; escolher manualmente com Del.

## Em andamento
- **"Cortinado" no boot**: a tela pisca/redesenha de cima para baixo até normalizar. Causas candidatas: (a) JPEG em vez de PNG (decodificação mais rápida),
  (b) `resolution 0` forçando troca de modo GOP, (c) `scan_delay 1`/scan de discos externos. Testando uma por vez; **primeiro JPEG**
  (ESP: `themes/rEFInd-grayscale-minimal/background.jpg`, `theme.conf` apontando para ele; `theme.conf.bak` e `background.orig.png` são os originais).
- Pendente: levar o fundo 4K/clamp para o repositório e o `install.sh` (gerar com Pillow, `python3-pil` já instalado neste device); decidir como lidar com outras resoluções.
- Pendente: dual-boot no mesmo SSD (precisa reduzir a raiz ext4 de um sistema live; `dualboot.sh` guia, ainda nunca executado de verdade).

## Convenções
- Textos bilíngues via `m "en" "pt"`. Usar `$SUDO`. Sempre fazer backup antes de sobrescrever algo na ESP.
- Mudar uma coisa por vez nos testes de boot (cada teste custa um reboot do usuário) e pedir foto/F10 para validar.
- Scripts só passaram em `bash -n` (shellcheck não instalado); `uninstall.sh` e `dualboot.sh` (partes que escrevem) nunca foram executados.

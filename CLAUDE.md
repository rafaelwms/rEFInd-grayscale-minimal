# CLAUDE.md — rEFInd Grayscale Minimal (arm64 / Radxa Dragon Q6A)

Projeto: instalador do rEFInd + tema grayscale. Meta: funcionar em arm64 (Radxa Dragon Q6A, QCS6490)
e permitir dual-boot Ubuntu + Windows 11. Idioma de trabalho com o usuário: português (BR).
O usuário quer acompanhar cada passo e fará os commits (não commitar; git sem identidade configurada).

## Arquivos
- `lib.sh` — helpers (`copy_theme`, idioma `m`, `has_nvram`, `find_esp`, `find_refind_dirs`, `is_refind_binary`, `pkg_install`).
- `install.sh` — menu: rEFInd / tema / ambos / assistente dual-boot. `./install.sh --entries` regenera só o bloco gerado do refind.conf.
- `uninstall.sh` — remove tema/rEFInd e restaura o carregador original do backup.
- `dualboot.sh [/dev/disco]` — analisa o disco; cria partição NTFS em espaço livre; guia redução da raiz (só de sistema live).
- `portable.sh` — rEFInd portátil em pendrive/SSD USB (rede de segurança). Lista só discos USB (nunca o disco de `/`); modo 1 usa partição FAT existente, modo 2 apaga o disco (exige digitar o nome do dispositivo). Copia binário, drivers, ícones, refind.conf-sample e tema para `EFI/BOOT`; **não** usa `refind-install`. **Rodado com um pendrive real (SanDisk Ultra 14,3 GB; sda1 vfat 200M vazio, modo 1; sda2 exFAT com dados do usuário intocada): arquivos corretos (bootaa64.efi == binário do pacote, fonte 30px, fundo 2560x1440, VERSION, refind.conf), ~4 MB usados; o script desmontou sozinho. Boot a partir do pendrive AINDA NÃO testado (Del -> escolher USB).**
- `tools/mac-restore-windows.sh` / `tools/linux-restore-windows.sh` — restauram a imagem do Windows (`dd` + zstd, ex.: `wd-windows-26H2.img.zst`, 37000 MiB = só as 3 partições, sem o espaço livre) num SSD de destino, detectado ao plugar (diff de discos); confirmação digitada, recusa disco do sistema, valida relendo o disco (sha256). O de Linux recria o GPT de backup com `sgdisk -e` (o macOS nega `gpt recover`). **Nunca executados por nós** (só `bash -n`); o `dd` manual equivalente foi testado e o Windows restaurado bootou na Radxa.
- `merge-linux.sh [-n]` — copia um Ubuntu (ext4) para o espaço livre de um SSD com Windows (GPT): destino e origem detectados ao plugar (ou origem = `/`), backup do GPT em `~/gpt-backup-*.bin`, `sgdisk -e`, partição `ubuntu-wd` (mkfs sem `orphan_file`/`metadata_csum_seed`), `rsync -aAXHx`, ajusta fstab/`refind_linux.conf`, mascara `90-loaderentry.install`, valida e desmonta. Só roda em Linux (macOS não tem ext4); pensado para o PC Desktop. **VALIDADO (2026-10-10)**: rodado no PC Desktop (x86_64) SEM nenhuma alteração, com dois cases Thunderbolt (TB4 e TB5), origem = SSD Micron 25094E7A6EFC (Ubuntu), destino = SSD com o Windows restaurado; sucesso de primeira. Boa prática: começar com `--dry-run`. Depois: pendrive com rEFInd -> entrar no Ubuntu copiado -> `./install.sh --windows-loader`.
- `tools/make_fonts.py` — gera as fontes com contorno (dev, requer Pillow). `fonts/<res>/font.png` — saída versionada.
- `theme.conf`, `icons/`, `selection_*.png`, `backgrounds/<LxA>/background.<nome>.png` — tema. Fundos em 1280x720, 1920x1080 (fallback), 2560x1440 e 3840x2160 × skulls/fender/gibson (cinza, canais [4,251], sem alpha). `install.sh --background` troca imagem/resolução.

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
- **"Cortinado" no boot** (baixa prioridade, aceito): a tela pisca/redesenha de cima para baixo até normalizar. O usuário vê o mesmo no Desktop dele, então não é
  específico da Q6A nem do tema; provavelmente é o redesenho normal do rEFInd na troca de modo de vídeo. Só retomar se o usuário pedir. Causas candidatas: (a) JPEG em vez de PNG,
  (b) `resolution 0` forçando troca de modo GOP, (c) `scan_delay 1`/scan de discos externos. Testando uma por vez.
  - (a) **JPEG FALHOU**: com `background.jpg` (3840x2160, q92, baseline, 4:4:4) o boot do NVMe terminou em tela preta / perda de sinal de vídeo.
    Causa provável (não provada): decodificador JPEG do rEFInd. Revertido para o PNG 4K (último estado bom). **Não usar JPG como banner.**
    O JPG de teste foi guardado em `/root/background.jpg.failed-*`.
  - Próximo: (b) tirar `resolution 0` do `theme.conf` (um teste por vez), depois (c).
- **Recuperação se o NVMe não boota**: o usuário sobe por um Ubuntu em case USB (`sda`) com rEFInd instalado, aponta para o NVMe e edita a ESP do NVMe (`/boot/efi`).
  Mudanças na ESP sempre com backup (`*.bak`) para reverter rápido. Após uma mudança de aparência, **o usuário testa 1 boot de cada vez** e só então seguimos.
- Feito: fundos por resolução em `backgrounds/` (instalador detecta via `/sys/class/drm/*/modes` e escolhe a mais próxima; ENTER = automático; VALIDADO pelo F10 em tela 4K, zero pixels coloridos fora dos ícones: 3840x2160, Gibson 1920x1080 (2x) e Fender 2560x1440 (1,5x); só 1280x720 (3x) não foi testada). Antes: `background.*.png` 3840x2160, cinza puro, canais em [4,251], sem alpha (originais 2816x1536 ficam no histórico do git).
  Descoberta: o defeito NÃO é reescala em geral: 2x (1080p→4K) e 1,5x (1440p→4K) saem limpos. O que gerava as raspas era especificamente a imagem antiga 2816x1536 (proporção 1,83, ≠ 16:9) ampliada ~1,36x com corte lateral.
  Então não é preciso preferir razões inteiras em `nearest_resolution`; manter proporção 16:9 nas imagens. Telas ultrawide/16:10 ainda não testadas. Marca d'água de estrela (Gemini) ainda visível no canto inferior direito dos fundos. `python3-pil` foi instalado neste device para gerar as imagens.
- Pendente: aplicar o novo fundo na ESP do usuário já está igual (skulls); trocar de fundo via `install.sh` copia o PNG 4K do repositório.
- Pendente: dual-boot no mesmo SSD (precisa reduzir a raiz ext4 de um sistema live; `dualboot.sh` guia, ainda nunca executado de verdade).

- **Seletor invisível (corrigido e VALIDADO no boot pelo usuário e pelo screenshot F10)**: o `selection_big.png` antigo era quase vazio (132 px com alpha em 256x256), então o seletor
  dos ícones grandes sumia em fundos escuros. Novo: quadrado arredondado branco translúcido (alpha 56) com borda (alpha 210, 4 px), 256x256. Já está na ESP do usuário.
  Chega à ESP junto com `./install.sh --background` (copy_theme copia `selection_*.png`). `selection_small.png` não foi alterado (ícones pequenos não aparecem neste menu).

- **Legibilidade da legenda ("Boot boot\vmlinuz…")** — o texto do rEFInd é uma imagem de glifos (PNG RGBA, 96 células: ASCII 32-126 + fallback), não há config de cor/contorno.
  `fonts/<res da TELA>/font.png`, gerado por `tools/make_fonts.py` (Ubuntu Mono **Bold** TTF; 720p=16px/contorno 1, 1080p=22px/1, 1440p=30px/2, 4K=40px/2),
  referenciado em `theme.conf` (`font themes/.../font.png`) e copiado por `copy_theme` conforme a resolução do MONITOR (não do fundo; tamanho é em px da tela).
  **DESCOBERTA (F10): o rEFInd decide a polaridade do glifo pelo brilho da região atrás do texto** (hipótese que explica todos os F10; não temos o código): a fonte do pacote é preta e sai branca em área escura;
  com o PNG "miolo branco + anel preto" a tela mostrou miolo preto + anel branco (texto curto sobre área escura => inverteu); com "miolo preto + anel branco" e texto de 40 px (largo, passa por destroços claros) a tela mostrou
  miolo preto + anel branco (não inverteu). Logo a cor do miolo pode variar entre fundos, mas o contorno é sempre o oposto e fica só por fora => legível em qualquer polaridade. Não dá para forçar branco por config;
  se um dia importar, escurecer a região do menu nos fundos (vinheta) baixaria o brilho médio. PNG atual: miolo PRETO + anel BRANCO, Bold, contorno 1-2 px. **VALIDADO no boot (F10 009/010)**: contorno só externo, miolo limpo, legível.

- **Atualização de instalação anterior (implementada, testada só no caminho "recusar")**: arquivo `VERSION` (1.1.0) na raiz; `copy_theme` grava `VERSION` e `install.info` (fundo escolhido, tela) em `themes/rEFInd-grayscale-minimal/` na ESP.
  `install.sh` (ao abrir) e `--update` rodam `check_existing`: tema sem VERSION = "legacy", versão ≠ atual = desatualizado -> oferece atualizar mantendo o fundo anterior. `--status` é só leitura (arch, NVRAM, ESP, espaço livre, temas, Windows na ESP, discos, efibootmgr) — pedir ao usuário que cole a saída para diagnosticar outras máquinas.
  **Bug corrigido**: `is_refind_binary` procurava "rEFInd" em ASCII, mas binários UEFI guardam UTF-16; agora procura `r\0E\0F\0I\0n\0d\0`. Antes isso fazia o `uninstall.sh` não reconhecer o rEFInd como carregador padrão (não restauraria o backup).
  Não atualiza o binário do rEFInd (só o tema); pendente decidir se `--update` deve comparar/atualizar `refind_<arch>.efi`.
- **Foco: casos gerais, não a história particular do usuário.** O Desktop dele (x86_64, UEFI com NVRAM, Secure Boot off, Windows+Ubuntu no mesmo NVMe de 2 TB após migrar o Ubuntu com `dd`;
  acesso SSH `rafaelwms@ASUS-ubuntu` via Tailscale, sudo sem senha, só leitura) é "exceção da exceção". **Decisão do usuário: não projetar para esse histórico** (verificação de `refind_linux.conf` obsoleto e limpeza de entrada órfã da NVRAM foram descartadas).
  Lição geral que ele revelou e foi implementada: **a ESP pode não estar montada nem no fstab**. `find_esp` agora: `REFIND_ESP` (override) -> vfat montado em /boot/efi, /efi, /boot -> partição GPT "EFI System" (c12a7328-…) montada
  temporariamente em `/run/refind-installer-esp` (prefere a do disco da raiz; várias candidatas => pede `REFIND_ESP=`); desmonta ao sair. **Ramo que monta VALIDADO** em namespace isolado (`sudo unshare -m`, desmontando /boot/efi só lá): achou a ESP pelo GUID, montou rw em /run/refind-installer-esp, `esp_device` correto, e a montagem foi desfeita ao fim do script (0 mounts). Técnica útil para testar sem tocar no sistema real.
  Também ficou: o caminho com NVRAM (`refind-install --yes`, desktops comuns) NUNCA foi executado por nós; só o sem NVRAM (Radxa). Tratar como não testado.
- Pendente (geral): `--update` ainda não atualiza o binário do rEFInd (só o tema); README deve dizer onde foi testado; testar em x86 real quando houver oportunidade (usar `--status` primeiro).

- **Teste uninstall + install do zero na Radxa (feito)**: backup da ESP em `~/esp-backup-20261008-2117.tgz` (168 MB; contém kernels da ESP). `uninstall.sh` (opção 3): restaurou o systemd-boot (md5 idêntico ao original 89f0…),
  removeu EFI/refind, o backup e o pacote. **Sobras achadas e corrigidas**: `EFI/BOOT/refind_aa64.efi` e `refind.conf-sample` (agora removidos). `/etc/refind.d/keys` fica (dpkg não remove dir não vazio; não é nosso).
  `install.sh` do zero: o pacote `refind` abre um diálogo **debconf** (`refind/install_to_esp`, padrão sim; sim = o pacote roda `refind-install --yes` sozinho) que **travou no terminal integrado** => `pkg_install` agora pré-responde `false` com `debconf-set-selections` e usa `DEBIAN_FRONTEND=noninteractive`.
  Reinstalação completa OK: BOOTAA64.EFI == refind_aa64.efi (cmp), backup do original salvo, tema/fonte/seletor/fundo com hashes idênticos aos do repositório, VERSION 1.1.0, install.info. **Boot real após reinstalar CONFIRMADO pelo usuário**; F10 009/010: fundo sem raspas, seletor e fonte 40px ok.
  Lição de teste: não use `pkill -f` com padrão que casa com o próprio comando (matou o shell); não passe respostas de diálogos por pipe no terminal integrado.
  Ao atualizar o pacote `refind` via apt, o postinst (se install_to_esp=true) roda `refind-install --yes` e NÃO atualiza nossa cópia em EFI/BOOT; com `false` (nosso preseed) nada é copiado: o binário em EFI/BOOT fica na versão antiga até alguém rodar o instalador. Pendente: `--update` atualizar o binário.

- **Monitor QHD (2560x1440) testado (F10 011/012)**: fundo 3840x2160 REDUZIDO pelo rEFInd (0,67x) sai limpo (zero cor fora dos ícones) => reduzir também é seguro. A fonte é por TELA: como o tema foi instalado com a Radxa em 4K (install.info screen=3840x2160),
  no QHD ficou a de 40px (grande, ~metade da largura; legível). Quem alterna monitores precisa reinstalar (`./install.sh --background`) para o tamanho de fonte do monitor principal; o rEFInd não troca de fonte em tempo de execução.

- **`--update` VALIDADO no Desktop do usuário (x86_64, NVRAM, ESP p5 fora do fstab)** via SSH `rafaelwms@192.168.3.2` (rede interna; Tailscale `ASUS-Ubuntu` também serve). Passos: backup `dd` da ESP (1 GiB, hash do arquivo == hash do device, em `~/esp-desktop-backup-20261008-2239.img` no Desktop), hashes/NVRAM antes e depois.
  Resultado: tema "legacy" detectado, ESP montada temporariamente (e desmontada ao fim), fundo skulls 4K + fonte 40px + seletor + theme.conf com hashes idênticos ao repositório; pasta antiga (LICENSE/Screenshots) removida; `refind.conf` ganhou só o bloco `scan_delay 1`.
  **NÃO mudaram**: refind_x64.efi, shimx64.efi, BOOTX64.EFI, bootmgfw.efi, BCD, nem a NVRAM (`efibootmgr -v` idêntico). Falta: reboot do usuário + F10 para ver o visual no Desktop.
  Lições: o shell de login do Desktop é **zsh** (não separa palavras em loops `for p in "a b"`; usar `ssh ... bash -s`); cuidado com `cmd | cut && echo ok` (o status é do último comando do pipe); `--status` agora monta a ESP em `ro` (`ESP_MOUNT_OPTS`).

- **Desktop após `--update`: 9 F10 (um por opção do menu) VALIDADOS**: 4K, zero pixels coloridos no fundo (141 px coloridos só numa faixa de 5 px na linha dos ícones pequenos), seletor grande e pequeno (disco redondo) visíveis, fonte 40px legível.
  Menu do Desktop: Windows (bootmgfw em EFI/Microsoft na ESP), Ubuntu, **gatinho = ícone "unknown" do "Fallback Boot Loader"** (`EFI/BOOT/BOOTX64.EFI` é o shim, mesmo hash de `EFI/ubuntu/shimx64.efi` => entrada duplicada do Ubuntu, comportamento padrão do rEFInd), e linha de ferramentas:
  chip(firmware), chave (MOK), info (about), power (shutdown), reset (reboot) e **chip (firmware) de novo**. Observado: o ícone/entrada "Reboot to Computer Setup Utility" aparece 2x; só o `theme.conf` define `showtools firmware` (refind.conf tem `#showtools` comentado).
  Causa NÃO confirmada (hipótese: o `showtools firmware` do tema soma-se à lista padrão que já inclui firmware). Correção candidata, não aplicada: remover a linha `showtools` do theme.conf ou listar as ferramentas explicitamente sem repetir; testar 1 reboot. Cosmético.

- **Screenshots do F10 ocupam a ESP**: ~25 MB cada em 4K (11 MB em QHD), gravados como `screenshot_NNN.bmp` na raiz da ESP (ou do volume de onde o rEFInd foi carregado) e nunca apagados.
  Limpos em 2026-10-08 com autorização do usuário: Radxa 12 arquivos (583M -> 842M livres) e Desktop 9 arquivos (764M -> 977M livres), via `find <ESP> -maxdepth 1 -name 'screenshot_*.bmp' -delete` (a ESP do Desktop foi montada rw temporariamente em ponto temporário e desmontada).
  **Cuidado com o plano do WD (ESP de só 200 MB)**: ~8 F10 em 4K encheriam a ESP; apagar após cada análise. **Implementado**: `./install.sh --clean-screenshots` (lista os `screenshot_*.bmp` na raiz da ESP, pede confirmação, apaga só eles; testado com arquivos de teste: recusar não apaga, aceitar apaga e não toca em outros arquivos) e dica no README (EN/PT).
  Pendente do usuário: responder às 3 perguntas do plano "Ubuntu -> SSD do Windows (WD 476,9 GB, ~410 GB livres, ESP 200M)" (direção, kernels na ESP apertados, se o Windows já iniciou nativo no slot da Radxa).

- **Windows no mesmo SSD da Radxa — decisão de projeto (conversa com o usuário)**: o usuário pensou em encolher a raiz ext4 e levar o Windows para o NVMe do Ubuntu, achando que mover o Linux exigiria "Windows portátil".
  Esclarecido: NÃO é preciso Windows portátil. Direção recomendada = **copiar o Ubuntu para o espaço livre do SSD do Windows** (WD 476,9 GB com ~63 GB usados, ~410 GB livres) enquanto o WD está no USB (só o Linux roda; o Windows nunca é iniciado); depois trocar o WD para o slot M.2, onde o Windows já inicia nativamente. Linux roda em USB ou NVMe sem problema (testado pelo usuário).
  Windows não roda via USB (instalado para NVMe; Windows To Go foi descontinuado) e o BCD guarda GUIDs de disco/partição, então mover o Windows para outro disco é arriscado (exigiria reconstruir o BCD). O NVMe atual do Ubuntu vira backup completo.
  `dualboot.sh` (encolher raiz + criar NTFS) continua útil para quem instala o Windows do zero. Próximo passo (aguardando o "topo" do usuário): olhar o WD pelo USB, SOMENTE LEITURA (partições, ESP de 200 MB, `EFI/BOOT/bootaa64.efi`).

- **WD (Windows) lido por USB, SÓ LEITURA, em 2026-10-08**: `sda` = WD PC SN740 série 240523805621, GPT d89e8046-…, 476,9 GiB (512110190592 bytes, MESMO tamanho do Micron mas NÃO mesmo modelo; o NVMe Ubuntu é Micron 2500 série 25094E7A6EFC, PTUUID 40a8ef52-…). Distinguir sempre pelo SERIAL.
  Partições WD: p1 ESP 200 MiB (EF00) | p2 MSR 16 MiB | p3 NTFS Windows 62 GiB (setores 444416–130484223) | p4 recuperação 762 MiB (setores 498554880–500115455, no MEIO do disco). Livre: 414 GiB em 2 blocos: ~175 GiB entre p3 e p4, e **~238 GiB contíguos no fim** (setores 500115456–1000215182).
  ESP do WD: 196 MB, 100 MB usados, **97 MB livres**; `EFI/Boot/bootaa64.efi` (3 MB) é CÓPIA IDÊNTICA de `EFI/Microsoft/Boot/bootmgfw.efi` (md5 c6026f80…) => é como o firmware da Radxa inicia o Windows; pode ser substituída por rEFInd (com backup .orig) porque o rEFInd chama o bootmgfw.
  Ubuntu atual: `/` 27 GB usados (home 14G, usr 7.3G, var 4.9G, opt 434M; docker vazio); fstab usa UUIDs (`/` b9a31fd6-…, `/boot/efi` DA29-B506); /boot da raiz já tem vmlinuz/initrd (o rEFInd boota daí, entrada "…from rootfs"); as cópias de kernel na ESP (52 MB, machine-id 6b11…) vêm do plugin `90-loaderentry.install` do kernel-install.
  Labels em uso: config, efi, rootfs => a nova partição precisa de label DIFERENTE (ex.: rootfs-wd). Plano para o Ubuntu novo no WD: partição no bloco de 238 GiB do fim; rsync da raiz; fstab novo (UUIDs); NÃO copiar `/boot/efi/<machine-id>`; mascarar `90-loaderentry.install` no Ubuntu novo (`/etc/kernel/install.d/90-loaderentry.install -> /dev/null`) para a ESP de 97 MB não encher; rEFInd na ESP do WD via `portable.sh` modo 1.

- **DUAL-BOOT NO MESMO SSD DA RADXA — EXECUTADO (2026-10-09)**: Ubuntu copiado para o SSD do Windows (WD, serial 240523805621) e SSDs trocados. Passos feitos: backups em `~/wd-backup/` (wd-gpt.bin, wd-esp.img = ESP original, wd-esp-pre-hijack.tgz); partição `sda5` 200 GiB ext4 label `ubuntu-wd` (UUID 88a1d080-…) no bloco livre do fim do disco;
  `mkfs.ext4 -O ^orphan_file,^metadata_csum_seed` (o mkfs 1.47 liga `metadata_csum_seed`, recurso INCOMPAT que o driver ext4 do rEFInd poderia recusar; features iguais às do ext4 original); instalei `rsync` (não existia); `rsync -aAXHx` com excludes (27 GB, ~16 min, depois conferido por dry-run: só caches/sessões vivos diferiam).
  Ajustes no sistema NOVO: `/etc/fstab` (UUID da raiz nova e ESP do WD 26BD-C323), `/boot/refind_linux.conf` (3 opções; a 3ª era `root=/dev/nvme0n1p3`, que no WD seria o NTFS do Windows), plugin `90-loaderentry.install` mascarado (symlink p/ /dev/null em /etc/kernel/install.d) para os kernels não encherem a ESP de 200 MB. rEFInd na ESP do WD via `portable.sh` modo 1 (guardou o bootmgfw como `bootaa64.efi.orig`). Provado por diff recursivo contra a imagem de backup: só `EFI/Boot/bootaa64.efi` mudou (+ arquivos novos); Microsoft/ e o BCD idênticos.
  **Resultado do 1º boot**: o Radxa foi DIRETO para o Windows (usuário não viu o rEFInd). Causa (hipótese forte): o firmware tem entrada própria apontando para `\EFI\Microsoft\Boot\bootmgfw.efi` e ignora `EFI/Boot/bootaa64.efi`. O usuário entrou no Linux pelo pendrive de resgate (que funciona).
  **Correção = modo `./install.sh --windows-loader`** (igual ao "hijack" do refind-install em modo BIOS; refind-install em UEFI+`--usedefault` NÃO faz isso): copia/verifica o bootmgfw original para `EFI/Microsoft/bootmgfw.efi` (aborta sem alterar nada se falhar ou se já existir diferente), copia o rEFInd (+refind.conf, drivers, icons, themes) como `EFI/Microsoft/Boot/bootmgfw.efi`, grava bloco `rEFInd-installer-windows` nas duas cópias (EFI/BOOT e Microsoft/Boot) com `default_selection` (Linux=`vmlinuz` por padrão, Windows=`bootmgfw`, ou `timeout -1`).
  `uninstall.sh` devolve o bootmgfw original (copia de volta, verifica com cmp, só então apaga os arquivos do rEFInd em Microsoft/Boot; se o original não estiver em EFI/Microsoft/bootmgfw.efi, recusa e avisa). `find_refind_dirs` agora inclui EFI/Microsoft/Boot (para --update/--background/uninstall).
  **VALIDADO**: o usuário rodou o modo, reiniciou e o rEFInd apareceu DIRETO do WD no slot M.2, sem pendrive; Ubuntu (`root=UUID=88a1d080`, `ubuntu-wd`) é o padrão; F10: fundo limpo no QHD, 3 entradas. Boot do Windows pelo rEFInd AINDA NÃO testado pelo usuário.
  **Defeito achado nos F10 e corrigido no repositório (ainda NÃO reaplicado na ESP)**: aparecia um 2º ícone do Windows (a stanza manual `menuentry "Windows"` somada à detecção automática de `EFI\Microsoft\bootmgfw.efi`); `dont_scan_dirs ESP:/EFI/Microsoft` NÃO a esconde (o rEFInd detecta o Windows por caminho especial). Agora `write_windows_block` NÃO cria stanza. Para aplicar: reexecutar `./install.sh --windows-loader` (idempotente, ENTER mantém Linux).
  Os 141 px "coloridos" de cada F10 são o LED azul do selo de disco de cada ícone (3 grupos de ~10 px, R≈105,G≈100,B≈150), não é defeito no fundo.
  Limitações conhecidas: (1) uma atualização do Windows pode restaurar o bootmgfw original (aí o Windows volta a iniciar direto; reaplicar o modo); (2) se o firmware usar o caminho de fallback `EFI/BOOT`, o rEFInd desse caminho pode listar `EFI\Microsoft\Boot\bootmgfw.efi` (que é o próprio rEFInd) como "Windows" — a entrada correta é a de `EFI\Microsoft\bootmgfw.efi`; (3) ESP do WD tem só 200 MB: 57 MB livres após 3 F10 em QHD (11 MB cada) => `./install.sh --clean-screenshots` após cada F10.
  O NVMe Micron (serial 25094E7A6EFC) com o Ubuntu antigo está intocado e serve de backup completo (pode ir no case USB). A classificação automática de segurança do Claude Code negou 1x a execução do modo (sobrescreve bootmgfw.efi); o usuário rodou-o manualmente.

## Convenções
- Textos bilíngues via `m "en" "pt"`. Usar `$SUDO`. Sempre fazer backup antes de sobrescrever algo na ESP.
- Mudar uma coisa por vez nos testes de boot (cada teste custa um reboot do usuário) e pedir foto/F10 para validar.
- Scripts só passaram em `bash -n` (shellcheck não instalado); `uninstall.sh` e `dualboot.sh` (partes que escrevem) nunca foram executados.

- **DUAL-BOOT FINAL FUNCIONANDO (2026-10-10)**: Windows 11 ARM 26H2 recriado com Rufus (Windows To Go) no WD, drivers instalados, atualizado e **imageado no Mac** (`dd` + zstd, 37000 MiB, sha256 87b8cb01…19ee; o hash do disco == hash da imagem), imagem **restaurada à mão com `dd` num 2º SSD** (Micron 512 GB serial 241948D235D8, mesmo tamanho exato: 1000215216 setores) que bootou na Radxa. O `gpt recover` do macOS nega ("operation not permitted"), mas o boot não depende do GPT de backup (`sgdisk -e` o recria no Linux).
  Layout atual (nvme0n1): p1 ESP 260M `1B01-2B39` | p2 MSR 128M | p3 NTFS `WIN11-Q6A` 231,1 GiB (estendido +200000 MB no Windows) | p4 ext4 `ubuntu-wd` 245,5 GiB (UUID 2b73f453-…), criada com `merge-linux.sh`.
  Conferido por leitura: fstab com os UUIDs novos, `90-loaderentry.install` mascarado, `EFI/BOOT/bootaa64.efi` == `EFI/Microsoft/Boot/bootmgfw.efi` == `refind_aa64.efi` (md5 878cfe35…), original em `EFI/Microsoft/bootmgfw.efi`, `default_selection vmlinuz`, sem stanza manual do Windows, sem screenshots, ESP com 152 MB livres. O usuário alternou Windows <-> Linux 2x de cada pelo rEFInd.
  Lição: o Windows To Go via USB só funciona depois de ser iniciado/"diagnosticado" no slot NVMe (via USB direto falhou; voltando ao NVMe ele se corrigiu). Se uma atualização do Windows restaurar o bootmgfw original, reaplicar `./install.sh --windows-loader` (checar com `md5sum` dos dois arquivos).

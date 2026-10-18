# CLAUDE.md — rEFInd Grayscale Minimal

Instalador do rEFInd + tema grayscale, pensado para arm64 (Radxa Dragon Q6A, QCS6490) e x86_64.
Permite dual-boot (Ubuntu + Windows 11 etc.) mesmo em firmware sem variáveis EFI (NVRAM).
Idioma de trabalho: português (BR). Textos dos scripts são bilíngues via `m "en" "pt"`.
Notas pessoais de máquinas/discos ficam em `CLAUDE.local.md` (não versionado).

## Arquivos
- `lib.sh` — helpers compartilhados (`copy_theme`, idioma `m`, `has_nvram`, `find_esp`, `find_refind_dirs`, `is_refind_binary`, `pkg_install`, funções do menu de boot `menu_*`).
- `install.sh` — menu: rEFInd / tema / ambos / assistente dual-boot / menu de boot. Flags: `--entries`, `--background`, `--status` (só leitura), `--update`,
  `--clean-screenshots`, `--windows-loader`, `--boot-menu`, `--custom-background [arquivo]`, `--icons white|black`, `--default last|linux|windows|none|<texto>`, `--timeout N`.
- `uninstall.sh` — remove tema/rEFInd e restaura o carregador original do backup.
- `dualboot.sh [/dev/disco]` — analisa o disco; cria partição NTFS em espaço livre; guia redução da raiz (só de sistema live). **Experimental.**
- `portable.sh` — rEFInd portátil em pendrive/SSD USB (rede de segurança). Só lista discos USB; não usa `refind-install`.
- `merge-linux.sh [-n]` — copia um Ubuntu (ext4) para o espaço livre de um SSD com Windows (GPT). Usar `--dry-run` primeiro. Só em Linux.
- `tools/{mac,linux}-restore-windows.sh` — restauram imagem do Windows (`dd` + zstd) num SSD de destino. **Não executados em testes** (só `bash -n`/shellcheck).
- `tools/make_fonts.py`, `tools/make_icons.py` — geram fontes/ícones (dev, requer Pillow). Saída versionada em `fonts/`, `icons/` e `icons-black/` (ícones pretos + quadros de seleção).
- `tools/make_background.py` — prepara a imagem do usuário (recorte 16:9, resolução, cinza opcional, canais [4,251], PNG) em `backgrounds/custom/` (fora do Git); `--brightness` mede o brilho atrás dos ícones. A cor dos ícones fica em `install.info` (`icons=`).
- `theme.conf`, `icons/`, `selection_*.png`, `backgrounds/<LxA>/background.<nome>.png` — tema. Fundos 1280x720, 1920x1080 (fallback), 2560x1440, 3840x2160.
- `VERSION` — versão do tema; gravada na ESP junto com `install.info` para detectar instalações antigas.

## Fatos importantes (não repetir erros)
- **Firmware sem NVRAM** (`/sys/firmware/efi/efivars` vazio): `efibootmgr` não funciona; o firmware só inicia `EFI/BOOT/BOOT<ARCH>.EFI` (ou uma entrada própria
  para o Windows). `refind-install --usedefault` não renomeia o binário para `BOOTAA64.EFI`; o instalador copia à mão, guarda backup do original e verifica com `cmp`.
- **Kernels**: o rEFInd acha o kernel em `/boot` sozinho; só geramos stanzas BLS se o kernel NÃO estiver em `/boot`. Bloco gerado entre `# BEGIN/END rEFInd-installer`.
- **ESP pode não estar montada** (nem no fstab): `find_esp` usa `REFIND_ESP`, depois vfat em /boot/efi, /efi, /boot, depois a partição GPT "EFI System" montada
  temporariamente em `/run/refind-installer-esp` (desmontada ao sair). A ESP só é legível com root.
- **Binários UEFI guardam texto em UTF-16**: `is_refind_binary` procura `r\0E\0F\0I\0n\0d\0`.
- **Pixels coloridos no fundo** vinham de uma imagem fora de 16:9 reescalada. Fundos em 16:9, cinza, canais em [4,251], sem alpha. Reduzir ou ampliar 16:9 sai limpo.
  **Não usar JPEG como fundo** (tela preta no teste); PNG sempre.
- **Fonte**: PNG de glifos (96 células); o tamanho é em pixels da TELA (não do fundo). O rEFInd inverte a polaridade do glifo conforme o brilho do fundo, então a fonte
  tem miolo preto + contorno branco para ficar legível nas duas polaridades. Trocar de monitor exige reinstalar (`--background`) para trocar a fonte.
- **Windows**: o BCD guarda GUIDs de disco/partição; não mover o Windows entre discos sem reconstruir o BCD. Para dual-boot no mesmo SSD, copie o Linux para o
  espaço livre do SSD do Windows (`merge-linux.sh`), não o contrário.
- **Modo `--windows-loader`**: quando o firmware inicia só `\EFI\Microsoft\Boot\bootmgfw.efi`, o original vai para `EFI/Microsoft/bootmgfw.efi` e o rEFInd ocupa
  `EFI/Microsoft/Boot/bootmgfw.efi`. Uma atualização do Windows pode restaurar o original: reaplicar o modo (comparar `md5sum` dos dois arquivos).
  O `uninstall.sh` devolve o original; se não o achar, recusa e avisa.
- **ext4 criado para o rEFInd**: `mkfs.ext4 -O ^orphan_file,^metadata_csum_seed` (recursos que o driver ext4 do rEFInd pode recusar). Mascarar
  `/etc/kernel/install.d/90-loaderentry.install` (symlink para `/dev/null`) no Linux copiado, para os kernels não encherem uma ESP pequena.
- **Screenshots do F10** ocupam a ESP (~25 MB cada em 4K) e nunca são apagados: `./install.sh --clean-screenshots`.
- **Joystick no menu de boot não é possível**: o UEFI só lê teclado/mouse de BOOT (HID classe 3, subclasse 1); gamepads genéricos são invisíveis ao firmware.
- **Raspberry Pi 5**: sem firmware UEFI; o `portable.sh` não funciona sem o firmware EDK2 do projeto rpi5-uefi (não testado).

## Menu de boot (`--boot-menu`)
- Estado no `refind.conf`, bloco `# BEGIN/END rEFInd-installer-menu`; linhas `#@ chave=valor` são metadados lidos de volta por `menu_read`, o resto são diretivas.
- `dont_scan_dirs` SUBSTITUI a lista a cada linha; use `dont_scan_dirs + RÓTULO:/EFI/BOOT` (o `+` é uma palavra separada). `default_selection` e `timeout` são de valor único.
- Entradas próprias: `menuentry` com `volume <PARTUUID>`, `loader`, `icon` (do tema ou PNG do usuário em `<dir>/icons-custom/`). O "Fallback" duplicado é escondido pelo rótulo.
- **"Última seleção" (`default_selection "+,vmlinuz"`) NÃO funcionou de forma confiável** em firmware sem NVRAM: o `vars/PreviousBoot` só registrou o Linux, nunca
  Windows nem entradas manuais. Preferir padrão fixo (`--default linux|windows`). Sem a linha `default_selection`, o rEFInd escolhe a primeira entrada (Windows).
  A política "Linux" usa `LINUX_MATCH` (lib.sh): `vmlinuz,Image,ubuntu,shim,grub`; só `vmlinuz` não casava no Desktop x86 (Ubuntu inicia pelo shim) e caía no Windows.

## Estado dos testes (diga isso no README)
- Validado: instalação/desinstalação em arm64 sem NVRAM, tema e fundos em 1080p/1440p/4K, `--update`, `--status`, `--clean-screenshots`, `--windows-loader`,
  `merge-linux.sh` (x86_64), `portable.sh` em UEFI, menu de boot com entrada própria.
- **Não testado**: caminho com NVRAM e `refind-install --yes` em instalação limpa, Secure Boot, `dualboot.sh` (partes que escrevem), scripts de restauração do Windows,
  `--update` NÃO atualiza o binário do rEFInd (só o tema), telas ultrawide/16:10, fundo 1280x720.

## Convenções
- Usar `$SUDO`. **Sempre fazer backup antes de sobrescrever algo na ESP.**
- Mudar uma coisa por vez nos testes de boot (cada teste custa um reboot) e validar por foto/F10.
- Testar sem tocar no sistema real: réplica da ESP (imagem FAT em loop + `REFIND_ESP`) e `sudo unshare -m` para o ramo "ESP não montada".
- Verificar com `bash -n` e `shellcheck` (0.11 instalado; ~27 avisos de nível note/warning conhecidos, nenhum grave).
- Armadilhas de shell: zsh não separa palavras em `for p in "a b"` (usar bash); `cmd | cut && echo ok` esconde o status; não usar `pkill -f` com padrão que casa com o
  próprio comando; não passar respostas de diálogos por pipe (o pacote `refind` abre um diálogo debconf, pré-respondido por `pkg_install`).
- Não commitar sem pedido do usuário.

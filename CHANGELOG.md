# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/). / Based on Keep a Changelog.

## [1.2.0] - 2026-10-17

### Added / Adicionado
- **Boot menu / Menu de boot** (`./install.sh --boot-menu`, `--default last|linux|windows|none|<text>`, `--timeout N`): default system, timeout, mouse/touch, and custom entries with an icon (e.g. Recalbox, Tails) that also hide the duplicate "Fallback boot loader". / Sistema padrão, tempo de espera, mouse/toque e entradas próprias com ícone (ex.: Recalbox, Tails), que também escondem o "Fallback boot loader" duplicado.
- `icons/os_gamepad.png` and `icons/os_tails.png` (generic privacy icon, own drawing, not the Tails logo), `tools/make_icons.py` (generator; never overwrites without `--force`). The wizard suggests the Tails icon for entries named tails/whonix. / Ícones de gamepad e de Tails (genérico, desenho próprio) e o gerador; o assistente sugere o ícone do Tails para entradas tails/whonix.
- `icons-black/`: every icon in pure black for light backgrounds (regenerate with `tools/make_icons.py`). / Todos os ícones em preto, para fundos claros.
- **Custom background / Fundo personalizado**: option 4 of the background menu or `./install.sh --custom-background [file]`; choose the resolution, grayscale by default; crops to 16:9, limits channels to 4-251, outputs PNG to `backgrounds/custom/` (`tools/make_background.py`, needs Pillow). / Opção 4 do menu de fundo ou `--custom-background [arquivo]`.
- `--windows-loader`: for firmware that only starts `\EFI\Microsoft\Boot\bootmgfw.efi` (keeps the original Windows loader and installs rEFInd in its place). / Para firmware que só inicia o `bootmgfw.efi`.
- `merge-linux.sh`: copies an Ubuntu (ext4) into the free space of a Windows SSD. / Copia um Ubuntu para o espaço livre de um SSD com Windows.
- `portable.sh`: rEFInd on a USB stick/SSD as a safety net. / rEFInd em pendrive/SSD USB como rede de segurança.
- `tools/{mac,linux}-restore-windows.sh`: restore a Windows disk image onto an SSD (not run end to end). / Restauram uma imagem do Windows num SSD (não executados de ponta a ponta).
- `--status` (read-only report), `--update` (refresh an older theme install), `--clean-screenshots` (delete F10 screenshots from the ESP). / Relatório somente leitura, atualização de instalação antiga e limpeza dos screenshots do F10.
- `shellcheck` is now part of the checks (0 errors; 4 intentional notes). / `shellcheck` passou a fazer parte das verificações.

### Changed / Alterado
- `uninstall.sh` now also restores the backup made by `portable.sh` (`EFI/Boot/boot<arch>.efi.orig`), verifies the copy with `cmp` before removing anything, removes `vars/`, and no longer says "completed successfully" after a refused or failed removal. / Agora restaura também o backup do `portable.sh`, confere a cópia com `cmp`, remove `vars/` e não diz mais "concluída com sucesso" após uma recusa ou falha.
- `find_esp` also finds an unmounted ESP by its GPT type and mounts it temporarily. / Também acha uma ESP desmontada pelo tipo GPT e a monta temporariamente.
- README (EN/PT): tested/untested platforms, experimental `dualboot.sh`, credits for the font (Ubuntu Font Licence 1.0), rEFInd (GPL) and icons (MIT). / Plataformas testadas e não testadas, `dualboot.sh` experimental e créditos de licença.

### Fixed / Corrigido
- `is_refind_binary` looked for ASCII text but UEFI binaries store UTF-16, so the uninstaller did not recognise rEFInd as the default loader. / O desinstalador não reconhecia o rEFInd como carregador padrão.
- `pkg_install` pre-answers the Debian `refind` package's debconf prompt, which hung the installer. / Pré-responde o diálogo do pacote `refind`, que travava o instalador.
- Manual stanza for Windows removed: it duplicated the entry rEFInd already detects. / Removida a entrada manual do Windows, que duplicava a detectada pelo rEFInd.

### Known limitations / Limitações conhecidas
- **"Remember last selection" (`--default last`) is unreliable on firmware without NVRAM**: it only remembered Linux in our tests. Prefer a fixed default. / A opção "lembrar a última seleção" não é confiável em firmware sem NVRAM; prefira um padrão fixo.
- A gamepad cannot select entries: UEFI only sees boot keyboards/mice. / Joystick não seleciona entradas: o UEFI só enxerga teclado/mouse de boot.
- `--update` refreshes the theme, not the rEFInd binary. / Atualiza o tema, não o binário do rEFInd.
- Not tested: clean install through the stock `refind-install` (x86/NVRAM path), Secure Boot, `dualboot.sh` (experimental), ultrawide/16:10 screens, 1280x720 background. / Não testado: instalação limpa pelo `refind-install` (x86/NVRAM), Secure Boot, `dualboot.sh`, telas ultrawide/16:10 e o fundo 1280x720.

## [1.1.0]

- Backgrounds per resolution (1280x720, 1920x1080, 2560x1440, 3840x2160), outlined fonts per screen size, visible selection frame, install on firmware without NVRAM with a backup of the original loader, `VERSION`/`install.info` for update detection. / Fundos por resolução, fontes com contorno por tamanho de tela, seletor visível, instalação sem NVRAM com backup do carregador original e arquivos de versão para detectar atualizações.

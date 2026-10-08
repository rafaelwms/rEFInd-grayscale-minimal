# rEFInd Grayscale Minimal Theme

* [English](#english)
* [Português (Brasil)](#português-brasil)

---

## English

### 🌌 About

A clean, minimalist, and grayscale-focused theme for the [rEFInd](https://www.rodsbooks.com/refind/) boot manager. This theme provides a sleek, monochromatic aesthetic paired with high-quality, AI-generated backgrounds, resulting in a modern multi-boot experience without distractions.

### ⚙️ Installation (via Script)

The easiest way to install both rEFInd and the Grayscale Minimal theme is by using the provided installation script. The script supports Debian/Ubuntu (`apt`), Arch Linux (`pacman`), Fedora (`dnf`), and openSUSE (`zypper`).

1. Open a terminal in the project's folder.
2. Make the script executable:
   ```bash
   chmod +x install.sh
   ```
3. Run the script:
   ```bash
   ./install.sh
   ```
4. Follow the on-screen prompts to choose your language, select what to install (rEFInd, the Theme, or both), and pick your favorite background image.

### 🧩 arm64 / boards without EFI variables (e.g. Radxa Dragon Q6A)

Some ARM firmwares expose no EFI variables, so `refind-install` copies files but cannot register a boot entry and the firmware keeps booting the old loader. `install.sh` detects this and installs rEFInd as the fallback loader (`EFI/BOOT/bootaa64.efi`) after saving a backup of the original in `EFI/refind-backup/`, and adds menu entries for the kernels in `/loader/entries`. `uninstall.sh` restores the backup.

### 🪟 Dual boot with Windows 11

`./dualboot.sh [/dev/disk]` analyzes the disk (partition table, free space, ESP), can create an NTFS partition in unallocated space, and guides shrinking the root partition (must be done from a live system, since ext4 cannot shrink while mounted). The ESP is shared; rEFInd detects `EFI/Microsoft` automatically. Windows on the QCS6490 is unofficial: expect missing drivers.

### 🛠️ Manual Installation (Theme Only)

If you prefer to install the theme manually, ensure you already have rEFInd installed.

1. **Locate your rEFInd directory:**
   Usually, this is located on your EFI partition. On most Linux systems, it is mounted at `/boot/efi/EFI/refind/`, `/boot/EFI/refind/`, or `/efi/EFI/refind/`.

2. **Create a themes folder:**
   Inside your `refind` directory, create a folder named `themes` (if it doesn't exist).

3. **Copy the theme:**
   Copy this repository's folder into your `themes` directory and rename it to `rEFInd-grayscale-minimal`.
   Path example: `/boot/efi/EFI/refind/themes/rEFInd-grayscale-minimal/`

4. **Enable the theme:**
   Open your main rEFInd configuration file (`refind.conf` located in the root of the refind folder) with root privileges and add this line at the very bottom:
   ```text
   include themes/rEFInd-grayscale-minimal/theme.conf
   ```

### 🎨 Changing the Background Picture

If you installed via the script, your chosen background was renamed to `background.png`.

If you want to change the background manually later:
1. Navigate to the theme folder on your EFI partition (`/boot/efi/EFI/refind/themes/rEFInd-grayscale-minimal/`).
2. You will find three original background options:
   - `background.skulls.png`
   - `background.fender.png`
   - `background.gibson.png`
3. Simply copy or rename your preferred image to `background.png`, overwriting the existing one.
4. Alternatively, open `theme.conf` and change the `banner` line to point to the desired image file directly:
   ```text
   banner themes/rEFInd-grayscale-minimal/background.skulls.png
   ```

### 🗑️ Uninstallation (via Script)

To remove the theme (and optionally rEFInd itself):

1. Open a terminal in the project's folder.
2. Make sure the script is executable:
   ```bash
   chmod +x uninstall.sh
   ```
3. Run the uninstallation script:
   ```bash
   ./uninstall.sh
   ```
4. Follow the prompts to select what you want to remove.

### 📜 Credits & License

* **Backgrounds:** Generated on Gemini Nano Banana 2. More backgrounds are coming soon!
* **Icons:** The base icons and selection frames are taken from the gorgeous [rEFInd-minimal-rog](https://github.com/Paradox-AT/rEFInd-minimal-rog) theme created by Paradox-AT.
* **License:** This project is open-source and available under the MIT License. See the `LICENSE` file for details.

---

## Português (Brasil)

### 🌌 Sobre

Um tema limpo, minimalista e focado em tons de cinza (grayscale) para o gerenciador de inicialização [rEFInd](https://www.rodsbooks.com/refind/). Este tema oferece uma estética elegante e monocromática, combinada com fundos gerados por IA de alta qualidade, resultando em uma experiência de multi-boot moderna e sem distrações.

### ⚙️ Instalação (via Script)

A maneira mais fácil de instalar tanto o rEFInd quanto o tema Grayscale Minimal é usando o script de instalação fornecido. O script tem suporte para Debian/Ubuntu (`apt`), Arch Linux (`pacman`), Fedora (`dnf`) e openSUSE (`zypper`).

1. Abra um terminal na pasta do projeto.
2. Torne o script executável:
   ```bash
   chmod +x install.sh
   ```
3. Execute o script:
   ```bash
   ./install.sh
   ```
4. Siga as instruções na tela para escolher seu idioma, selecionar o que instalar (rEFInd, o Tema ou ambos) e escolher sua imagem de fundo favorita.

### 🧩 arm64 / placas sem variáveis EFI (ex.: Radxa Dragon Q6A)

Alguns firmwares ARM não expõem variáveis EFI: o `refind-install` copia os arquivos mas não registra a entrada de boot, e o firmware segue iniciando o carregador antigo. O `install.sh` detecta isso e instala o rEFInd como carregador padrão (`EFI/BOOT/bootaa64.efi`), salvando antes um backup do original em `EFI/refind-backup/`, e adiciona entradas para os kernels de `/loader/entries`. O `uninstall.sh` restaura o backup.

### 🪟 Dual boot com Windows 11

`./dualboot.sh [/dev/disco]` analisa o disco (tabela de partições, espaço livre, ESP), cria uma partição NTFS no espaço não alocado e orienta a redução da partição raiz (só a partir de um sistema live, pois o ext4 não encolhe montado). A ESP é compartilhada; o rEFInd detecta `EFI/Microsoft` sozinho. Windows no QCS6490 não é oficial: esperem drivers faltando.

### 🛠️ Instalação Manual (Apenas o Tema)

Se você preferir instalar o tema manualmente, certifique-se de já ter o rEFInd instalado.

1. **Localize o diretório do seu rEFInd:**
   Geralmente, ele está localizado na sua partição EFI. Na maioria dos sistemas Linux, ele é montado em `/boot/efi/EFI/refind/`, `/boot/EFI/refind/` ou `/efi/EFI/refind/`.

2. **Crie uma pasta "themes":**
   Dentro do seu diretório `refind`, crie uma pasta chamada `themes` (se ela ainda não existir).

3. **Copie o tema:**
   Copie a pasta deste repositório para dentro do seu diretório `themes` e renomeie-a para `rEFInd-grayscale-minimal`.
   Exemplo de caminho: `/boot/efi/EFI/refind/themes/rEFInd-grayscale-minimal/`

4. **Ative o tema:**
   Abra o arquivo de configuração principal do rEFInd (`refind.conf` localizado na raiz da pasta do refind) com privilégios de root e adicione esta linha bem no final:
   ```text
   include themes/rEFInd-grayscale-minimal/theme.conf
   ```

### 🎨 Trocando a Imagem de Fundo

Se você instalou através do script, o fundo escolhido foi renomeado para `background.png`.

Se você quiser alterar o plano de fundo manualmente depois:
1. Navegue até a pasta do tema na sua partição EFI (`/boot/efi/EFI/refind/themes/rEFInd-grayscale-minimal/`).
2. Você encontrará três opções de imagens de fundo originais:
   - `background.skulls.png`
   - `background.fender.png`
   - `background.gibson.png`
3. Simplesmente copie ou renomeie sua imagem preferida para `background.png`, substituindo a existente.
4. Alternativamente, abra o arquivo `theme.conf` e altere a linha `banner` para apontar diretamente para o arquivo de imagem desejado:
   ```text
   banner themes/rEFInd-grayscale-minimal/background.skulls.png
   ```

### 🗑️ Desinstalação (via Script)

Para remover o tema (e opcionalmente o próprio rEFInd):

1. Abra um terminal na pasta do projeto.
2. Certifique-se de que o script seja executável:
   ```bash
   chmod +x uninstall.sh
   ```
3. Execute o script de desinstalação:
   ```bash
   ./uninstall.sh
   ```
4. Siga as instruções para selecionar o que você deseja remover.

### 📜 Créditos e Licença

* **Planos de Fundo:** Gerados no Gemini Nano Banana 2. Mais planos de fundo em breve!
* **Ícones:** Os ícones base e as bordas de seleção foram retirados do lindo tema [rEFInd-minimal-rog](https://github.com/Paradox-AT/rEFInd-minimal-rog) criado por Paradox-AT.
* **Licença:** Este projeto é de código aberto e está disponível sob a Licença MIT. Veja o arquivo `LICENSE` para mais detalhes.

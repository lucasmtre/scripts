#!/bin/bash
# Script de instalação completa do ambiente Flutter no Ubuntu 22.04 ou 24.04
# Por: Lucas

set -e  # Encerra em caso de erro

### 1. Atualizar sistema e instalar dependências básicas
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa \
    clang ninja-build pkg-config libgtk-3-dev mesa-utils openjdk-17-jdk

### 2. Instalar Flutter SDK se não existir
FLUTTER_DIR="$HOME/APPS/flutter"
TEMP_DIR="$HOME/APPS/temp"
if [ ! -d "$FLUTTER_DIR" ]; then
  mkdir -p "$TEMP_DIR/flutter"
  cd "$TEMP_DIR/flutter"
  curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.4-stable.tar.xz
  tar xf flutter_linux_3.32.4-stable.tar.xz
  mv flutter "$FLUTTER_DIR"
fi

### 3. Adicionar Flutter ao PATH no ~/.bashrc se necessário
if ! grep -q 'flutter/bin' ~/.bashrc; then
  echo -e '\n# Flutter SDK' >> ~/.bashrc
  echo 'export PATH="$HOME/APPS/flutter/bin:$PATH"' >> ~/.bashrc
fi

### 4. Instalar Android Studio se não existir
ANDROID_STUDIO_DIR="/opt/android-studio"
if [ ! -d "$ANDROID_STUDIO_DIR" ]; then
  cd "$HOME/Downloads"
  wget -O android-studio.tar.gz https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2024.1.1.18/android-studio-2024.1.1.18-linux.tar.gz
  mkdir -p "$TEMP_DIR/android-studio"
  tar -xzf android-studio.tar.gz -C "$TEMP_DIR/android-studio"
  sudo mv "$TEMP_DIR/android-studio/android-studio" /opt/
  sudo ln -sf /opt/android-studio/bin/studio.sh /usr/local/bin/android-studio
fi

### 5. Aceitar licenças Android SDK (pode falhar se Android Studio ainda não tiver rodado)
flutter doctor --android-licenses || true

### 6. Instalar VS Code se não estiver presente
if ! command -v code &>/dev/null; then
  cd "$HOME/Downloads"
  wget -O vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
  sudo apt install ./vscode.deb -y
fi

### 7. Instalar extensão Flutter no VS Code
if code --list-extensions | grep -q Dart-Code.flutter; then
  echo "Extensão Flutter já instalada no VS Code."
else
  code --install-extension Dart-Code.flutter || true
fi

### 8. Limpar pastas temporárias
if [ -d "$TEMP_DIR" ]; then
  rm -rf "$TEMP_DIR"
fi

### 9. Recarregar ambiente (nova shell) e finalizar
exec bash  # Recarrega bashrc

echo -e "\nAmbiente Flutter configurado com sucesso. Rodando flutter doctor:\n"
flutter doctor

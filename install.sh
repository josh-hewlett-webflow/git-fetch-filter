#!/bin/bash
set -e

INSTALL_DIR="${HOME}/bin"
SCRIPT_NAME="git-fetch-filter"
# TODO: Update this URL to where the script is hosted
SCRIPT_URL="https://raw.githubusercontent.com/OWNER/REPO/main/git-fetch-filter.sh"

echo "Installing $SCRIPT_NAME..."

# Create install directory if needed
mkdir -p "$INSTALL_DIR"

# Download the script
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Ensure ~/bin is on PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    shell_rc=""
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    fi

    if [[ -n "$shell_rc" ]]; then
        echo "" >> "$shell_rc"
        echo "# Added by $SCRIPT_NAME installer" >> "$shell_rc"
        echo 'export PATH="$HOME/bin:$PATH"' >> "$shell_rc"
        echo "Added $INSTALL_DIR to PATH in $shell_rc (restart your shell or run: source $shell_rc)"
    else
        echo "Warning: Could not find .zshrc or .bashrc. Add $INSTALL_DIR to your PATH manually."
    fi
fi

echo "Installed to $INSTALL_DIR/$SCRIPT_NAME"
echo ""

# Drop straight into cron setup
"$INSTALL_DIR/$SCRIPT_NAME" -c

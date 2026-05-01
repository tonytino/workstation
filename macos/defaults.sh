#!/usr/bin/env bash
# Curated macOS defaults. Each setting is a `defaults write` so it can be
# reversed with the same key + `defaults delete` (or revert by re-running
# System Settings adjustments). Re-running this script is idempotent.

set -euo pipefail

echo "→ Applying macOS defaults..."

# ── Keyboard ────────────────────────────────────────────────────────────────
# Faster key repeat (smallest values; defaults are 6 / 25 in System Settings).
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable press-and-hold accent menu so vim h/j/k/l repeat works.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# ── Screenshots ─────────────────────────────────────────────────────────────
mkdir -p "${HOME}/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture disable-shadow -bool true

# ── Finder ──────────────────────────────────────────────────────────────────
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"  # list view default
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"  # search current folder by default

# ── Dock ────────────────────────────────────────────────────────────────────
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock minimize-to-application -bool true

# ── Save / Print dialogs ────────────────────────────────────────────────────
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# ── Misc ────────────────────────────────────────────────────────────────────
# Don't write .DS_Store on network/USB volumes.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Restart affected services so changes take effect immediately.
killall Dock Finder SystemUIServer 2>/dev/null || true

echo "✓ macOS defaults applied. Some changes (e.g. KeyRepeat) require a logout/login."

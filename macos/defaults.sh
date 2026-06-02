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

# Note: ApplePressAndHoldEnabled is left at the macOS default. Disabling it
# would let vim h/j/k/l repeat in some terminal editors, but it also breaks
# the press-and-hold accent menu, which is more useful day-to-day. Arrow
# keys still repeat fine in Vim regardless.

# ── Screenshots ─────────────────────────────────────────────────────────────
mkdir -p "${HOME}/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"
defaults write com.apple.screencapture type -string "png"
# Window-screenshot drop shadow stays enabled (macOS default) per user
# preference -- the shadow is part of the desired aesthetic.

# ── Finder ──────────────────────────────────────────────────────────────────
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# Hidden files stay hidden by default (use Cmd+Shift+. to toggle per-window).
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
# View styles: icnv=Icon, Nlsv=List, clmv=Column, glyv=Gallery.
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"  # column view default
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"  # search current folder by default

# ── Dock ────────────────────────────────────────────────────────────────────
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock show-recents -bool false
# minimize-to-application stays at default (false) -- minimized windows
# remain as separate previews on the right side of the Dock rather than
# collapsing into their app icon.

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

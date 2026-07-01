# Homebrew cask for Hadron for Mac.
#
# This is the source-of-truth template. `Scripts/release.sh` rewrites the
# `version` and `sha256` lines after each notarized build. To publish:
# copy this file into your tap repo (e.g. hadron-memory/homebrew-tap under
# Casks/) and commit. Users then install with:
#
#   brew install --cask hadron-memory/tap/hadron-menu-bar
#
# The sign-in token lives in the macOS Keychain, not on disk — use the app's
# "Sign Out" to remove it (a cask `zap` can't reach Keychain items).
cask "hadron-menu-bar" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/hadron-memory/hadron-macapp/releases/download/v#{version}/HadronMenuBar-#{version}.dmg",
      verified: "github.com/hadron-memory/hadron-macapp/"
  name "Hadron for Mac"
  desc "Menu bar app for browsing Hadron memories, task nodes, and search"
  homepage "https://github.com/hadron-memory/hadron-macapp"

  depends_on macos: ">= :sonoma"

  app "HadronMenuBar.app"
end

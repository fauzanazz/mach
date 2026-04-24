# Homebrew Tap Setup

This guide explains how to set up the `fauzanazz/mach` Homebrew tap for distribution.

## 1. Create the tap repository

Create a new GitHub repo named `homebrew-mach` (the `homebrew-` prefix is required).

```bash
gh repo create homebrew-mach --public --description "Homebrew tap for mach"
```

## 2. Add the cask formula

Create `Casks/mach.rb` in the tap repo:

```ruby
cask "mach" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/fauzanazz/mach/releases/download/v#{version}/mach.zip"
  name "mach"
  desc "Mechanical keyboard sounds for your Mac"
  homepage "https://github.com/fauzanazz/mach"

  depends_on macos: ">= :ventura"

  app "mach.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/mach.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.fauzanazz.mach.plist",
    "~/mach-debug.log",
  ]
end
```

## 3. Get the SHA256

After creating a release, compute the checksum:

```bash
curl -L https://github.com/fauzanazz/mach/releases/download/v0.1.0/mach.zip -o mach.zip
shasum -a 256 mach.zip
```

## 4. Update on new releases

When you tag a new release:

1. Update `version` in the cask formula
2. Recompute and update `sha256`
3. Commit and push to the tap repo

## Usage

Users install with:

```bash
brew tap fauzanazz/mach
brew install --cask mach
```

The `postflight` script automatically removes the quarantine attribute, so users don't need to bypass Gatekeeper manually.

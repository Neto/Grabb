# Grabb

A macOS app that downloads videos, audio, and Instagram content from links. It has a native SwiftUI interface.

Download only content that you have permission to save.

## Features

- Downloads from YouTube, Instagram, TikTok, Vimeo, and other sites that yt-dlp supports. Availability depends on the site and the content.
- Quality selector for each video, up to 4K when available. MP3 audio extraction.
- H.264 and AAC output that plays in QuickTime. Grabb converts the file when necessary.
- Instagram photos and carousels. Experimental support for Stories and highlights.
- Download queue, History tab with Download Again, and a destination folder setting.
- Separate browser cookie settings for videos and for Instagram Stories.
- First run tutorial with an animated example. Open it again with Help > Show Tutorial.
- yt-dlp, ffmpeg, ffprobe, and deno are inside the app.

## Requirements

- Mac with Apple Silicon (arm64).
- macOS 15 or later.

## Usage

1. Paste a link, or drag a link into the window.
2. Choose the quality.
3. Click Download.

Files go to the Downloads folder by default. Change the folder in Preferences.

## Browser cookies

Some content needs a login. Grabb uses yt-dlp to read cookies from the browser that you select. You do not enter a password in Grabb. Cookies can contain session data, so select a browser only when you need it.

- **Cookies for videos** applies to YouTube, Reels, Instagram posts, and other links. The options are None (default), Automatic, or a specific browser.
- **Cookies for Instagram Stories** applies to Stories and highlights. Select a browser where you are signed in to Instagram.

To read Safari cookies, Grabb needs Full Disk Access in System Settings > Privacy & Security. This permission gives broad access, so grant it only if you trust your copy of the app.

## Diagnostics

In Preferences > Engine, turn on detailed diagnostics to record tool versions and errors. Logs are in `~/Library/Logs/Grabb/`. Grabb removes cookie, token, and credential values from the logs. Check the logs for local paths before you share them.

## Build from source

Install Xcode with the command line tools and Homebrew. Then install the dependencies:

```
brew install xcodegen ffmpeg deno dylibbundler python@3.11
```

Build the app:

```
git clone https://github.com/Neto/Grabb.git
cd Grabb
./scripts/bundle-helpers.sh
xcodegen generate
xcodebuild -project Grabb.xcodeproj -scheme Grabb -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build
```

`DEVELOPMENT_TEAM` in `project.yml` is the Apple team of the original author. Change it to your own team before you build.

`scripts/make-installer.sh` creates a signed and notarized package. It needs a Developer ID Installer certificate and a notarytool profile.

## Credits

- Original project (DLYT): Mentor Neto.
- Features added in the BaixaTudo version: Ricardo Cavallini. These are the quality selector, Instagram photos and Stories, separate cookie settings, the diagnostics, and the yt-dlp packaging changes. Git history keeps his authorship.
- Tools: yt-dlp, FFmpeg, and Deno, under their own licenses.
- The experimental Stories fix is adapted from yt-dlp PR 17885. See `Grabb/Resources/Diagnostics/STORIES-FIX.md`.

## License

This repository has no license file. Publishing the source code does not grant a license to reuse, change, or redistribute it.

(c) 2026 Mentor Neto and the contributors.

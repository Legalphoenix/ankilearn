# MnemonicMaker (SwiftUI, macOS)

Create mnemonic **images** and **audio** for phrase/translation pairs, then export an **Anki-ready** deck.

## Features
- Drop a `.txt`/`.tsv` file (UTF-8) of `phrase<TAB>translation`
- Global **image style** prompt + per-card assembled prompts
- **TTS** audio per card (OpenAI Audio API)
- Export `deck.tsv` + `media/` with `<img src="...">` and `[sound:...]`

## Setup
1. Open the Xcode project you create for a macOS SwiftUI App (or add these files to a new app project).
2. Run the app → **MnemonicMaker → Set OpenAI API Key…**. The key is saved in Keychain.
3. Import your TXT/TSV, configure Image/Audio, choose an export folder, **Start Build**.
4. In Anki: **File → Import → deck.tsv**, map fields. Anki copies media and syncs as usual.

## Notes
- Image model: `gpt-image-1` via `/v1/images/generations`.
- TTS model: `gpt-4o-mini-tts` via `/v1/audio/speech`.
- Images are saved as JPEG unless you change `output_format` to PNG/WEBP.
- Files are written into the chosen export folder as `deck.tsv` and `media/*`.

> Keep your API key out of source control. It's stored securely via Keychain.

# Bark Flow

Bark Flow is a local dictation app for Apple silicon Macs. It runs Conway Research's Bark 3.0 speech models on your Mac and can paste the transcript into the active text field.

## Install and use

Requires macOS 15 or later and an Apple silicon Mac. Copy Bark Flow to Applications before opening it. This early build is ad hoc signed and is not notarized, so macOS may block it on first launch. If you trust the source, see [Apple's instructions for opening an app that is not notarized](https://support.apple.com/102445).

Allow microphone access when prompted. For automatic text insertion, enable Bark Flow in System Settings > Privacy & Security > Device Control and Data Access (or Accessibility on older macOS). Place the cursor in an editor, press Option + Space to start, and Option + Return to stop. The floating listening window also has a Stop button. Shortcuts can be changed in Settings. The app remains in the menu bar after its window is closed.

The first model load can take several minutes as macOS prepares its machine learning cache. Longer recordings take longer to process. Choose a recording limit from 30 seconds to 10 minutes in Settings. Imported audio is limited to two minutes. Recognition is English only and produces verbatim text, including fillers.

## Models and privacy

Bark 3.0 Plus is included. Select Bark 3.0 or Bark 3.0 Pro in the speech model menu to download it from Hugging Face on first use. The approximate model downloads are 200 MB and 1.25 GB respectively, and macOS needs additional disk space for its compiled caches. Downloads are checked against pinned publisher hashes and stored in the user's Application Support folder. Subsequent selection uses the local copy. An internet connection is needed for the initial download only.

Speech recognition runs locally. Audio and transcripts are not sent to a transcription service. The latest transcript is held in memory until the app quits; automatic insertion uses the clipboard, which can retain text if paste confirmation is unavailable. No account or subscription is required.

## Build from source

Install Swift 6.2 or later, Xcode Command Line Tools, Python 3 and NumPy. Then run `./build.sh`. The build script downloads and verifies pinned Plus model files, prepares its decoder, builds the app and signs it locally. FluidAudio is pinned to revision `a00964e1aa8eff99c4bce80bc9c8ff2d4dd1568d`. Set `BARK_FLUID_AUDIO_PATH` to use a local checkout and `BARK_APP_OUTPUT` to change the app destination. The resulting development build is not notarized.

The app has not yet been independently tested on a wide range of Macs. If a model download fails, select the model again or use Try loading again. Model preparation and memory use vary by device.

## Credits

Bark 3.0, Plus and Pro are by [Conway Research](https://huggingface.co/ConwayResearch), under CC BY 4.0, derived from NVIDIA Parakeet through Moondream Parakeet Ultra. The native Plus and standard runtime adapts the publisher's Core ML reference. FluidAudio is licensed under Apache 2.0. See [third-party notices](Resources/THIRD-PARTY-NOTICES.txt) and the licenses and notices included with the model downloads.

The project source is publicly visible; no separate license for Bark Flow's own code has been specified. Third-party components remain subject to their respective licenses.

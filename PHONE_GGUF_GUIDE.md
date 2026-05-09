# Use a local GGUF model on iPhone

NeuraL does not download models for you in the local-only flow. Bring your own `.gguf` file, install/run the app on your iPhone, then load the file from the **Models** tab.

## 1. Make sure the GGUF will fit your iPhone

A DeepSeek-distilled Qwen GGUF can work if it is a normal text-generation GGUF and the quantized file fits comfortably in device memory.

Good first choices:

- 1B-2B parameter models on most modern iPhones.
- 3B parameter models on higher-memory devices, preferably quantized such as Q4_K_M or smaller.
- Keep the context modest at first; the default app config starts at a practical local context size.

Avoid for the current app path:

- `.safetensors`, `.bin`, `.pth`, or unquantized model directories.
- Vision/mmproj GGUF files by themselves; the current load button expects the text LLM GGUF.
- Models that are larger than the free storage/RAM on your phone.

## 2. Install the app on your phone

Use one of these routes:

### Option A: Xcode install from a Mac

```bash
git submodule update --init --recursive
xcodegen generate
open NeuraL.xcodeproj
```

Then in Xcode:

1. Select your iPhone as the run destination.
2. Select your Apple developer team in Signing & Capabilities.
3. Press **Run**.

### Option B: No local Xcode: GitHub Actions + KSign

1. Open GitHub Actions for this repo.
2. Run **Build NeuraL IPA** on the branch that contains the app changes.
3. Download the `NeuraL-unsigned` artifact and unzip it if needed.
4. Import `NeuraL-unsigned.ipa` into KSign.
5. Sign it with your own certificate/provisioning profile.
6. Install the signed IPA with your normal KSign flow.

See [Build without local Xcode and install with KSign](NO_XCODE_KSIGN_GUIDE.md) for the detailed no-Xcode path.

## 3. Put the GGUF on the iPhone

Any Files-accessible location is fine:

- AirDrop the `.gguf` to the iPhone and save it to **Files**.
- Put it in **iCloud Drive** and let it sync.
- Copy it into **On My iPhone** with Finder or another file provider.

Keep the file name ending in `.gguf` so the file picker can identify it.

## 4. Load the model in NeuraL

1. Open **NeuraL**.
2. Tap the **Models** tab.
3. Tap **Load GGUF Model**.
4. Pick your DeepSeek/Qwen `.gguf` from Files.
5. Wait for the **Model Status** card to show metadata.
6. Switch to **Chat** and send a message.

When you pick a model, NeuraL copies it into the app's Application Support `Models` directory. If you load another file with the same name, the app replaces its stored copy.

## Troubleshooting

| Symptom | What to try |
| --- | --- |
| The file is greyed out | Confirm the filename ends in `.gguf` and the file is in Files/iCloud/On My iPhone. |
| Load fails immediately | Confirm it is the text LLM GGUF, not a tokenizer-only, mmproj, embedding, or adapter file. |
| App closes or iOS kills it | Use a smaller quantization/model, free memory, restart the phone, or try a shorter context. |
| Generation is very slow | Try a smaller model, lower quantization size, or let the phone cool before loading. |
| Chat says no model is loaded | Return to Models, load the GGUF again, and wait for Model Status before chatting. |

For the first smoke test, ask something short like: `Say hello in one sentence.`

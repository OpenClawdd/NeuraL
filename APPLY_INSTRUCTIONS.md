# Applying and validating this branch

This branch is a normal Git branch patch. It should be merged through the pull request created for the current branch; do **not** create or push a separate `ipa-candidate-local` branch unless you intentionally want a new release branch.

## Fresh clone workflow

```bash
git clone https://github.com/OpenClawdd/NeuraL.git
cd NeuraL
git fetch --all --prune
git checkout codex/build-dreamstate-local-cognition-layer
```

If you need to update the branch with `main`, merge `origin/main` and resolve any conflicts deliberately. Avoid blanket `git checkout --ours ...` conflict resolution because it can discard fixes from `main` and recreate the same conflicts for the next developer.

## If you cannot find the branch on GitHub

The Codex sandbox commits changes locally first. If the GitHub branch is not visible in the branch picker, the commits have not been pushed from an environment with GitHub access yet. From a clone that contains the commits, run:

```bash
git status --short --branch
git log --oneline -5
git push origin HEAD:codex/build-dreamstate-local-cognition-layer
```

After that push completes, refresh GitHub Actions and select `codex/build-dreamstate-local-cognition-layer` when running the IPA workflow.

## No local Xcode path

If you do not want to use Xcode locally, run the GitHub Actions **Build NeuraL IPA** workflow and sign the resulting unsigned IPA with KSign. See [Build without local Xcode and install with KSign](NO_XCODE_KSIGN_GUIDE.md).

## Local macOS prerequisites

Only use this section if you want to build locally. Local iOS builds require full Xcode and XcodeGen:

```bash
brew install xcodegen
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

If `xcodebuild` reports that the active developer directory is `/Library/Developer/CommandLineTools`, full Xcode is not selected and iOS archive builds will fail before this project is compiled.

## Local validation commands

```bash
git submodule update --init --recursive
xcodegen generate
xcodebuild -project NeuraL.xcodeproj -scheme NeuraL -destination 'generic/platform=iOS' build
```

For an unsigned archive/IPA-style build, use:

```bash
xcodebuild -project NeuraL.xcodeproj \
  -scheme NeuraL \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath ./DerivedData \
  archive -archivePath ./NeuraL.xcarchive
```

## Run the IPA workflow

1. Open GitHub → `OpenClawdd/NeuraL` → **Actions**.
2. Select **Build NeuraL IPA**.
3. Click **Run workflow**.
4. Select the PR branch.
5. Download the `NeuraL-unsigned` artifact when the workflow finishes.
6. Sign `NeuraL-unsigned.ipa` with KSign if you are using your own certificate.

## What this patch contains

- Local llama.cpp inference through `InferenceOrchestrator` and `LlamaCppBridge`.
- DreamState / Neural Trace wiring.
- Minimal local GGUF model import UI in `ModelsView`.
- XcodeGen llama.cpp build settings in `project.yml`.
- GitHub Actions IPA workflow at `.github/workflows/build.yml`.

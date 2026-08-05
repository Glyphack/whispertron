#!/bin/sh

set -e

cd "$(dirname "$0")"

# Download the default bundled model
# This model will be included in the app bundle and used as the default
# Additional models can be downloaded at runtime to ~/.whispertron/models/
mkdir -p whispertron/models/
MODEL="ggml-small.en-q5_1"

FILE_PATH="whispertron/models/model.bin"
if [ -f "$FILE_PATH" ]; then
    echo "Whisper model already downloaded."
else
    echo "Downloading bundled model: $MODEL"
    curl -L -o "$FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL.bin?download=true"
fi

WHISPER_VERSION="v1.9.2"

FILE_PATH="whisper-$WHISPER_VERSION-xcframework.zip"
if [ -f "$FILE_PATH" ] && [ -d whisper_xcframework ]; then
    echo "Whisper framework already downloaded."
else
    echo "Downloading whisper framework: $WHISPER_VERSION"
    curl -L -o "$FILE_PATH" "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER_VERSION/$FILE_PATH"
    rm -rf whisper_xcframework
    unzip -q -d whisper_xcframework "$FILE_PATH"
fi

xcodebuild -project whispertron.xcodeproj -scheme whispertron -configuration Release build ARCHS=arm64

echo "you'll probably need to reset accessibility permissions before the build will work:"
echo ""
echo "    tccutil reset Accessibility com.glyphack.whispertron"
echo ""
echo "then try running:"
echo ""
echo "    open ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app"
echo ""
echo "or copy to your app folder for usage:"
echo ""
echo "    ditto ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app /Applications/whispertron.app"

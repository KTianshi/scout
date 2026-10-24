# Third-party notices

## OpenClicky — MIT License
https://github.com/jasonkneen/openclicky — Copyright (c) 2026 Jason Kneen

Lookout does not include OpenClicky source files. These parts are adapted from its patterns (rewritten, not copied verbatim):
- `Sources/LookoutCore/PointTags.swift` — the `[POINT:x,y:label]` tag protocol and the trailing-partial-tag stripping used while streaming (from `CompanionManager+PointTagParsing.swift`).
- `Sources/LookoutApp/Overlay*.swift` — transparent, click-through, all-spaces overlay window setup (from `OverlayWindow.swift`).
- `Sources/LookoutApp/Voice.swift` — Apple Speech streaming transcription session shape (from `AppleSpeechTranscriptionProvider.swift`).
- Screenshot → model-coordinate scaling approach (from `ElementLocationDetector.swift`).

MIT License text:

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

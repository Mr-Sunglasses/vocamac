# Canary empty-decode reproduction sample

`canary-empty-decode-4s.wav` — 4.0s, 16 kHz mono, English speech.

`sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8` (sherpa-onnx 1.13.7)
returns an empty `text` for this file. Scaling every sample by 1.001 makes
it decode correctly; 0.999 does not.

Attached to a bug report against k2-fsa/sherpa-onnx.

# Third-party source

`src/vendor/miniaudio/miniaudio.h` is the unchanged official miniaudio 0.11.25
single-header distribution by David Reid, including its embedded decoder
sources and license notices. The complete upstream license is preserved at
`src/vendor/miniaudio/LICENSE`. This package uses upstream's **MIT No
Attribution** alternative; upstream also offers the Unlicense alternative.
The header and license hashes and exact commit are in SOURCE_PROVENANCE.json.

Source: https://github.com/mackron/miniaudio/tree/0.11.25

Tests generate their own WAV signals. MP3 and FLAC fixtures are encoded locally
with an installed ffmpeg executable for testing only; no ffmpeg binary or
third-party recording is bundled or required at runtime.

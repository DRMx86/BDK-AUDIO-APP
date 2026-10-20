These are actual 16 × 16 RGBA frames captured from the app-owned Windows x64 LED
library packaged in preview 0.5.7+15. `provenance.json` records its hash, the exact
settings, sampling order, selected frames and individual fixture hashes.

They reproduce the gallery's bounded representative-frame selection, including
the unusually sparse Meteor Shower frame. Widget raster tests use these recorded
native outputs to check gallery visibility and label contrast without depending
on a platform FFI library. They are test data, never app runtime assets or claims
of identical random sequences across platforms.

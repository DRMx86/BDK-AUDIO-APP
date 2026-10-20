#ifndef BDK_AUDIO_CONNECTION_SNAPSHOT_H_
#define BDK_AUDIO_CONNECTION_SNAPSHOT_H_
#include "audio_connection_model.h"
namespace bdk_audio {
// Local read-only OS metadata; no inquiry, pairing, connection or stream open.
AudioSnapshotReport ReadWindowsAudioSnapshot();
}
#endif

#include "bdk_audio_platform.h"
int bdk_platform_probe(BdkAudioFile,bdk_audio_info&){return BDK_AUDIO_UNSUPPORTED;}
int bdk_platform_decode(BdkAudioFile,uint32_t,uint64_t,uint32_t,int16_t*){return BDK_AUDIO_UNSUPPORTED;}

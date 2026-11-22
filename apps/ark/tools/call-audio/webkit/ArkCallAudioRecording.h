// Development WebKit builds only: copy next to ArkCallAudioInternalUnit.h to compile in call recording (the debug
// dump, ARK_CALL_AUDIO_DUMP). A WebKit built for release leaves this file out, so its unit can't record.
#pragma once
#define ARK_CALL_AUDIO_RECORDING 1

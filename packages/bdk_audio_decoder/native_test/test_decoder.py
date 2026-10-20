"""Real C ABI tests; fixtures are generated locally, never played or uploaded."""
import ctypes as c
from concurrent.futures import ThreadPoolExecutor
import math
from pathlib import Path
import shutil
import struct
import subprocess
import unittest
import wave

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'; FIX=BUILD/'fixtures'
DLL=BUILD/'native/Release/bdk_audio_decoder.dll'
MAX_SAMPLES=102378
class Probe(c.Structure):
    _fields_=[('sample_rate',c.c_uint32),('channels',c.c_uint32),('frames',c.c_uint64)]

def fixtures():
    FIX.mkdir(parents=True,exist_ok=True)
    with wave.open(str(FIX/'stereo.wav'),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000)
        w.writeframes(b''.join(struct.pack('<hh',10000,-2000) for _ in range(96000)))
    with wave.open(str(FIX/'ramp.wav'),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000)
        w.writeframes(b''.join(struct.pack('<h',(i*37)%20000-10000) for i in range(32000)))
    raw=(FIX/'ramp.wav').read_bytes(); extra=b'JUNK'+struct.pack('<I',3)+b'abc\0'
    chunked=raw[:12]+extra+raw[12:];chunked=chunked[:4]+struct.pack('<I',len(chunked)-8)+chunked[8:]
    (FIX/'chunks.wav').write_bytes(chunked)
    (FIX/'truncated.wav').write_bytes(raw[:-100])
    with wave.open(str(FIX/'max.wav'),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(8000)
        w.writeframes(struct.pack('<h',4000)*MAX_SAMPLES)
    (FIX/'invalid.bin').write_bytes(b'not an audio file')
    shutil.copyfile(FIX/'ramp.wav',FIX/'Tiếng Việt 日本語 🎵.wav')
    executable=shutil.which('ffmpeg')
    if not executable:raise RuntimeError('ffmpeg required for real MP3/FLAC/float fixtures')
    for name,codec in [('real.mp3','libmp3lame'),('real.flac','flac'),('float.wav','pcm_f32le')]:
        subprocess.run([executable,'-nostdin','-v','error','-y','-i',str(FIX/'ramp.wav'),'-c:a',codec,str(FIX/name)],check=True)
        if name.endswith(('.mp3','.flac')):
            encoded=(FIX/name).read_bytes();(FIX/('cut-'+name)).write_bytes(encoded[:len(encoded)//2])
    for name,codec,extra in [('real.m4a','aac',['-movflags','+faststart']),('real.aac','aac',['-f','adts']),('real.ogg','libvorbis',[])]:
        subprocess.run([executable,'-nostdin','-v','error','-y','-i',str(FIX/'ramp.wav'),'-c:a',codec,*extra,str(FIX/name)],check=True)
        encoded=(FIX/name).read_bytes();(FIX/('cut-'+name)).write_bytes(encoded[:len(encoded)//2])
    # Six channels force FFmpeg's WAV extensible format; no native playback API.
    subprocess.run([executable,'-nostdin','-v','error','-y','-i',str(FIX/'ramp.wav'),'-ac','6','-c:a','pcm_s24le',str(FIX/'extensible.wav')],check=True)
    (FIX/'empty.wav').write_bytes(raw[:44][:40]+b'\0\0\0\0')
    (FIX/'tagged.aac').write_bytes(b'ID3\x04\x00\x00\x00\x00\x00\x00'+(FIX/'real.aac').read_bytes())
    shutil.copyfile(FIX/'real.m4a',FIX/'Âm thanh 日本語 🎧.m4a')
    # Device QA also exercises extension-independent cache files, 44.1-kHz
    # stereo AAC, and selected windows later than the initial decoder pre-roll.
    shutil.copyfile(FIX/'real.m4a',FIX/'cache.audio')
    with wave.open(str(FIX/'long.wav'),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000)
        w.writeframes(b''.join(struct.pack('<h',(i*37)%20000-10000) for i in range(96000)))
    for source,name,extra in [('long.wav','long.m4a',[]),('stereo.wav','stereo.m4a',['-ar','44100'])]:
        subprocess.run([executable,'-nostdin','-v','error','-y','-i',str(FIX/source),*extra,'-c:a','aac','-movflags','+faststart',str(FIX/name)],check=True)
    subprocess.run([executable,'-nostdin','-v','error','-y','-stream_loop','59','-i',str(FIX/'ramp.wav'),'-c:a','aac','-movflags','+faststart',str(FIX/'long120.m4a')],check=True)
    floating=(FIX/'float.wav').read_bytes();position=floating.index(b'data')+8
    (FIX/'nan-float.wav').write_bytes(floating[:position]+struct.pack('<f',float('nan'))+floating[position+4:])
    with (FIX/'too-large.wav').open('wb') as f:f.truncate(64*1024*1024+1)

class DecoderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):fixtures()
    def setUp(self):
        self.assertTrue(DLL.is_file(),'Native decoder ABI has not been implemented/built')
        self.lib=c.CDLL(str(DLL))
        self.lib.bdk_audio_probe.argtypes=[c.c_char_p,c.c_int32,c.POINTER(Probe)]
        self.lib.bdk_audio_decode_segment.argtypes=[c.c_char_p,c.c_int32,c.c_uint32,c.c_uint64,c.c_uint32,c.POINTER(c.c_int16),c.c_uint32,c.POINTER(c.c_uint32)]
    def probe(self,name):
        p=str(FIX/name).encode('utf8');info=Probe()
        code=self.lib.bdk_audio_probe(p,len(p),c.byref(info));return code,info
    def decode(self,name,rate,start,count,capacity=None):
        p=str(FIX/name).encode('utf8');out=(c.c_int16*max(1,capacity or count))();written=c.c_uint32(999)
        code=self.lib.bdk_audio_decode_segment(p,len(p),rate,start,count,out,capacity or count,c.byref(written))
        return code,list(out)[:written.value],written.value
    def test_probe_real_wav_mp3_flac_float_extensible(self):
        for name in ['ramp.wav','real.mp3','real.flac','float.wav','extensible.wav','chunks.wav']:
            with self.subTest(name=name):
                code,p=self.probe(name);self.assertEqual(code,0);self.assertEqual(p.sample_rate,16000)
                self.assertGreaterEqual(p.frames,32000);self.assertGreater(p.channels,0)
                code,samples,n=self.decode(name,16000,123,300)
                self.assertEqual((code,n),(0,300));self.assertTrue(any(samples))
    def test_mono_downmix_all_four_rates_and_output_frame_seek(self):
        for rate in [22050,16000,11025,8000]:
            code,samples,n=self.decode('stereo.wav',rate,rate,200)
            self.assertEqual((code,n),(0,200));self.assertLessEqual(max(abs(s-4000) for s in samples),2)
        code,samples,n=self.decode('ramp.wav',16000,123,200)
        self.assertEqual(code,0);self.assertEqual(samples,[(i*37)%20000-10000 for i in range(123,323)])
    def test_resampled_segment_matches_full_conversion(self):
        for name in ['ramp.wav','real.mp3','real.flac']:
            full=self.decode(name,11025,0,15000);part=self.decode(name,11025,6000,1000)
            self.assertEqual((full[0],part[0]),(0,0))
            self.assertLessEqual(max(abs(a-b) for a,b in zip(full[1][6000:7000],part[1])),2,name)
    def test_unicode_windows_path(self):
        self.assertEqual(self.probe('Tiếng Việt 日本語 🎵.wav')[0],0)
        self.assertEqual(self.decode('Tiếng Việt 日本語 🎵.wav',8000,10,100)[0],0)
    def test_exact_maximum_output_preserves_neighboring_memory(self):
        path=str(FIX/'max.wav').encode('utf8');out=(c.c_int16*(MAX_SAMPLES+2))();out[0]=out[-1]=12345
        samples=c.cast(c.byref(out,2),c.POINTER(c.c_int16));written=c.c_uint32()
        code=self.lib.bdk_audio_decode_segment(path,len(path),8000,0,MAX_SAMPLES,samples,MAX_SAMPLES,c.byref(written))
        self.assertEqual((code,written.value),(0,MAX_SAMPLES));self.assertEqual((out[0],out[-1]),(12345,12345))
        self.assertEqual((out[1],out[-2]),(4000,4000))
    def test_missing_compressed_tail_cannot_complete_selected_late_segment(self):
        for name in ['cut-real.mp3','cut-real.flac']:
            code,_,written=self.decode(name,16000,31000,1000)
            self.assertNotEqual(code,0,name);self.assertEqual(written,0)
    def test_independent_parallel_calls_have_no_shared_decoder_state(self):
        def run(i):return self.decode('real.flac' if i&1 else 'ramp.wav',16000,123,100)
        with ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(run,range(24)))
        for code,samples,written in results:
            self.assertEqual((code,written),(0,100));self.assertEqual(samples[0],123*37-10000)
    def test_conversion_can_reach_the_last_output_frame_at_every_rate(self):
        for name in ['ramp.wav','real.mp3','real.flac','float.wav','extensible.wav']:
            code,info=self.probe(name);self.assertEqual(code,0)
            for rate in [22050,16000,11025,8000]:
                total=info.frames*rate//info.sample_rate
                code,_,written=self.decode(name,rate,total-100,100)
                self.assertEqual((code,written),(0,100),(name,rate))
    def test_nonfinite_float_pcm_is_rejected(self):
        code,_,written=self.decode('nan-float.wav',16000,0,100)
        self.assertEqual((code,written),(5,0))
    def test_windows_native_aac_and_m4a_are_real_decoders(self):
        for name in ['real.m4a','real.aac']:
            code,info=self.probe(name);self.assertEqual(code,0,name)
            self.assertEqual((info.sample_rate,info.channels),(16000,1));self.assertGreaterEqual(info.frames,32000)
            for rate in [22050,16000,11025,8000]:
                code,samples,n=self.decode(name,rate,1000,400)
                self.assertEqual((code,n),(0,400),(name,rate));self.assertTrue(any(abs(s)>100 for s in samples))
            code,_,n=self.decode(name,16000,info.frames-100,100)
            self.assertEqual((code,n),(0,100),name)
    def test_windows_native_resampling_and_truncation(self):
        for name in ['real.m4a','real.aac']:
            full=self.decode(name,11025,0,15000);part=self.decode(name,11025,6000,1000)
            self.assertEqual((full[0],part[0]),(0,0),name)
            self.assertLessEqual(max(abs(a-b) for a,b in zip(full[1][6000:7000],part[1])),2,name)
            code,_,n=self.decode('cut-'+name,16000,31000,1000)
            self.assertNotEqual(code,0,name);self.assertEqual(n,0)
    def test_ogg_is_actual_native_decode_or_explicitly_unsupported(self):
        code,info=self.probe('real.ogg')
        self.assertIn(code,[0,4])
        if code==0:
            code,samples,n=self.decode('real.ogg',16000,1000,100)
            self.assertEqual((code,n),(0,100));self.assertTrue(any(samples))
    def test_aac_id3_prefix_is_not_mistaken_for_an_mp3_stream(self):
        code,info=self.probe('tagged.aac');self.assertEqual(code,0)
        self.assertEqual((info.sample_rate,info.channels),(16000,1))
        code,samples,n=self.decode('tagged.aac',16000,1000,100)
        self.assertEqual((code,n),(0,100));self.assertTrue(any(samples))
    def test_native_compressed_unicode_path(self):
        self.assertEqual(self.probe('Âm thanh 日本語 🎧.m4a')[0],0)
        self.assertEqual(self.decode('Âm thanh 日本語 🎧.m4a',8000,1000,100)[0],0)
    def test_invalid_and_truncated_inputs_never_synthesize_silence(self):
        for name in ['invalid.bin','truncated.wav','empty.wav','missing.wav']:
            self.assertNotEqual(self.probe(name)[0],0,name)
            code,_,written=self.decode(name,16000,0,100)
            self.assertNotEqual(code,0,name);self.assertEqual(written,0)
    def test_size_range_capacity_and_argument_limits(self):
        self.assertEqual(self.probe('too-large.wav')[0],3)
        for rate,start,count,capacity in [(44100,0,100,100),(16000,0,0,1),(16000,0,MAX_SAMPLES+1,MAX_SAMPLES+1),(16000,31999,2,2),(16000,2**64-1,10,10),(16000,0,100,99)]:
            code,_,n=self.decode('ramp.wav',rate,start,count,capacity)
            self.assertNotEqual(code,0);self.assertEqual(n,0)
        info=Probe();self.assertNotEqual(self.lib.bdk_audio_probe(b'bad\0path',8,c.byref(info)),0)
        self.assertEqual(self.lib.bdk_audio_probe(b'\xff',1,c.byref(info)),10)
        self.assertNotEqual(self.lib.bdk_audio_probe(None,0,c.byref(info)),0)

if __name__=='__main__':unittest.main(verbosity=2)

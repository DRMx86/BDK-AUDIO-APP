#include "bdk_led_engine.h"
#include <array>
#include <cmath>
#include <cstring>
#include <memory>
#include <new>
#include "led/led_effects.h"

namespace {
// Field construction is separate from the source effects and their driver.
// Coefficients and scratch memory belong to one context and are allocated only
// when that owner first requests a field. No frame/settings/RNG state is read.
struct LightFieldCache {
    std::array<float,BDK_LED_CORE_FIELD_WIDTH*16> coreWeights;
    std::array<float,BDK_LED_HALO_FIELD_WIDTH*16> haloWeights;
    std::array<float,BDK_LED_CORE_FIELD_WIDTH*16*4> horizontal;
    std::array<float,16*16*4> source;
    float haloSigma=0;

    LightFieldCache(){
        coefficients(coreWeights.data(),BDK_LED_CORE_FIELD_WIDTH,-4.0,24.0,0.8);
    }
    static void coefficients(float* weights,int width,double minimum,double span,double sigma){
        const double normalization=1.0/(2.5066282746310005024*sigma);
        for(int node=0;node<width;++node){
            const double position=minimum+node*span/(width-1);
            for(int led=0;led<16;++led){
                const double distance=(position-(led+0.5))/sigma;
                weights[node*16+led]=static_cast<float>(
                    std::exp(-0.5*distance*distance)*normalization);
            }
        }
    }
    void field(const float* weights,int width,float* output){
        // Horizontal pass: 16 source cells -> field width, on each source row.
        // Four independent channels allow native SIMD without changing the
        // accumulation order. Scratch alpha is zero; final alpha is opaque.
        for(int x=0;x<width;++x){
            const float* wx=weights+x*16;
            for(int row=0;row<16;++row){
                float color[4]={0,0,0,0};
                for(int led=0;led<16;++led){
                    const float* pixel=source.data()+(row*16+led)*4;
                    for(int channel=0;channel<4;++channel)color[channel]+=pixel[channel]*wx[led];
                }
                std::memcpy(horizontal.data()+(x*16+row)*4,color,sizeof(color));
            }
        }
        // Vertical pass: 16 intermediate rows -> field height. Output writes
        // stay contiguous; each x has its 16 source-row values adjacent.
        for(int y=0;y<width;++y){
            const float* wy=weights+y*16;
            for(int x=0;x<width;++x){
                float color[4]={0,0,0,0};
                const float* column=horizontal.data()+x*16*4;
                for(int row=0;row<16;++row){
                    for(int channel=0;channel<4;++channel)color[channel]+=column[row*4+channel]*wy[row];
                }
                const int offset=(y*width+x)*4;
                output[offset]=color[0];output[offset+1]=color[1];output[offset+2]=color[2];
                output[offset+3]=1.0f;
            }
        }
    }
    void compute(const uint8_t* rgba,float sigma,float* core,float* halo){
        for(int pixel=0;pixel<16*16;++pixel){
            const int offset=pixel*4;
            const float alpha=rgba[offset+3]/255.0f;
            for(int channel=0;channel<3;++channel)source[offset+channel]=(rgba[offset+channel]/255.0f)*alpha;
            source[offset+3]=0;
        }
        if(haloSigma!=sigma){
            coefficients(haloWeights.data(),BDK_LED_HALO_FIELD_WIDTH,0.0,16.0,sigma);
            haloSigma=sigma;
        }
        field(coreWeights.data(),BDK_LED_CORE_FIELD_WIDTH,core);
        field(haloWeights.data(),BDK_LED_HALO_FIELD_WIDTH,halo);
    }
};

std::unique_ptr<LedEffect> makeEffect(int id) {
    switch(id) {
        case 0:return std::make_unique<SpectrumBarsEffect>();
        case 1:return std::make_unique<BeatPulseEffect>();
        case 2:return std::make_unique<RippleEffect>();
        case 3:return std::make_unique<FireEffect>();
        case 4:return std::make_unique<PlasmaEffect>();
        case 5:return std::make_unique<MatrixRainEffect>();
        case 6:return std::make_unique<VUMeterEffect>();
        case 7:return std::make_unique<StarfieldEffect>();
        case 8:return std::make_unique<WaveEffect>();
        case 9:return std::make_unique<FireworksEffect>();
        case 10:return std::make_unique<RainbowWaveEffect>();
        case 11:return std::make_unique<ParticleBurstEffect>();
        case 12:return std::make_unique<KaleidoscopeEffect>();
        case 13:return std::make_unique<FrequencySpiralEffect>();
        case 14:return std::make_unique<BassReactorEffect>();
        case 15:return std::make_unique<MeteorShowerEffect>();
        case 16:return std::make_unique<BreathingEffect>();
        case 17:return std::make_unique<DNAHelixEffect>();
        case 18:return std::make_unique<AudioScopeEffect>();
        case 19:return std::make_unique<BouncingBallsEffect>();
        case 20:return std::make_unique<LavaLampEffect>();
        case 21:return std::make_unique<AmbientEffect>();
        default:return nullptr;
    }
}
struct Context {
    LedDriverSPI driver;
    std::unique_ptr<LedEffect> effect;
    std::unique_ptr<LightFieldCache> lightFields;
    int id=-1;
    uint8_t brightness=255;
    uint8_t demoFrame=0;
    // App-owned idle inputs, independent of the copied effects' global random
    // helpers. Only Spectrum demo renders advance this reproducible clock.
    uint32_t spectrumRandom=0xa341316c;
    float spectrumLevel[3]={0.12f,0.18f,0.09f};
    float spectrumTarget[3]={0.12f,0.18f,0.09f};
    uint8_t spectrumTargetFrames[3]={0,0,0};
    uint8_t settings[10]={128,255,0,128,0,128,255,0,50,0};
};
void ambient(Context& c){
    if(c.id==21)static_cast<AmbientEffect*>(c.effect.get())->setSettings(c.settings,10);
}
float bounded(float v,float low,float high){
    if(!std::isfinite(v))return low;
    return v<low?low:v>high?high:v;
}
uint32_t spectrumRandom(Context& c){
    uint32_t value=c.spectrumRandom;
    value^=value<<13;value^=value>>17;value^=value<<5;
    return c.spectrumRandom=value;
}
AudioData spectrumDemo(Context& c){
    for(int band=0;band<3;++band){
        if(c.spectrumTargetFrames[band]==0){
            const float unit=(spectrumRandom(c)>>8)*(1.0f/16777216.0f);
            // More quiet targets than loud ones leave room for visible bar
            // motion. Independent 0.5-2 s targets avoid a shared sine loop.
            c.spectrumTarget[band]=0.006f+0.68f*unit*unit;
            c.spectrumTargetFrames[band]=static_cast<uint8_t>(15+spectrumRandom(c)%46);
        }
        --c.spectrumTargetFrames[band];
        // At the app's 30 FPS, approach targets smoothly without using wall
        // time. This convex step keeps all three normalized inputs in [0,1].
        c.spectrumLevel[band]+=(c.spectrumTarget[band]-c.spectrumLevel[band])*0.06f;
    }
    AudioData audio{};
    audio.bass=c.spectrumLevel[0];
    audio.mid=c.spectrumLevel[1];
    audio.high=c.spectrumLevel[2];
    return audio;
}
}
void* bdk_led_create(){
    auto c=std::unique_ptr<Context>(new(std::nothrow)Context());
    if(!c||!bdk_led_select(c.get(),0))return nullptr;
    return c.release();
}
void bdk_led_destroy(void* p){delete static_cast<Context*>(p);}
int bdk_led_select(void* p,int id){
    if(!p||id<0||id>=22)return 0;
    auto& c=*static_cast<Context*>(p);
    if(c.id==id)return 1;
    auto e=makeEffect(id);if(!e)return 0;
    c.driver.clear();e->init(&c.driver);c.effect=std::move(e);c.id=id;c.demoFrame=0;
    c.settings[9]=static_cast<uint8_t>(id);ambient(c);return 1;
}
int bdk_led_settings(void* p,const uint8_t* v,int n){
    if(!p||!v||n!=10||v[0]>=22||v[1]>100||v[2]>100||v[9]>=5)return 0;
    auto& c=*static_cast<Context*>(p);if(!bdk_led_select(p,v[0]))return 0;
    c.brightness=static_cast<uint8_t>((v[1]*163+32)>>6);
    uint8_t settings[10]={c.brightness,v[3],v[4],v[5],v[6],v[7],v[8],v[9],v[2],v[0]};
    std::memcpy(c.settings,settings,10);ambient(c);return 1;
}
int bdk_led_render(void* p,const float* v,uint8_t flags,int demo,uint8_t* out,int cap){
    if(!p||!v||!out||cap<1024)return 0;
    auto& c=*static_cast<Context*>(p);
    if(demo&&c.id==0){
        // Keep Spectrum's source rendering intact; replace only its periodic
        // demo inputs when the caller explicitly authorizes demo/idle mode.
        c.effect->update(spectrumDemo(c));
    }
    else if(demo&&(c.id==11||c.id==15)){
        // These source demo wrappers increment their frame both before and
        // inside update(), so their even-period triggers never fire on a cold
        // start. Supply the same demo inputs from the app's own render clock;
        // the copied effect classes and their audio-reactive updates stay intact.
        c.demoFrame=static_cast<uint8_t>((c.demoFrame+1)%60);
        AudioData a{};
        a.beat=(c.demoFrame%30)==0;
        a.beatIntensity=(c.id==11||a.beat)?0.7f:0.0f;
        a.bass=c.id==11?0.3f:(c.demoFrame%20==0?0.8f:0.1f);
        c.effect->update(a);
    }
    else if(demo)c.effect->updateDemo();
    else{
        AudioData a{};a.bass=bounded(v[0],0,1);a.mid=bounded(v[1],0,1);a.high=bounded(v[2],0,1);
        a.bassDB=bounded(v[3],-120,0);a.midDB=bounded(v[4],-120,0);a.highDB=bounded(v[5],-120,0);
        a.beatIntensity=bounded(v[6],0,1);a.beat=(flags&1)!=0;a.audioActive=(flags&2)!=0;
        c.effect->update(a);
    }
    for(int y=0;y<16;++y)for(int x=0;x<16;++x){
        RGB pixel=c.driver.getPixelXY(x,y).scale(c.brightness);int i=(y*16+x)*4;
        out[i]=pixel.r;out[i+1]=pixel.g;out[i+2]=pixel.b;out[i+3]=255;
    }
    return 1024;
}
const char* bdk_led_name(int id){
    const char* names[22]={"Spectrum","Beat Pulse","Ripple","Fire","Plasma","Matrix Rain",
        "VU Meter","Starfield","Wave","Fireworks","Rainbow Wave","Particle Burst",
        "Kaleidoscope","Freq Spiral","Bass Reactor","Meteor Shower","Breathing","DNA Helix",
        "Audio Scope","Bouncing Balls","Lava Lamp","Ambient"};
    return id>=0&&id<22?names[id]:nullptr;
}
int bdk_led_light_fields(void* p,const uint8_t* source,int sourceLength,float haloSigma,
                         float* core,int coreCapacity,float* halo,int haloCapacity){
    if(!p||!source||sourceLength!=1024||!core||!halo||
       coreCapacity<BDK_LED_CORE_FIELD_FLOATS||haloCapacity<BDK_LED_HALO_FIELD_FLOATS||
       !std::isfinite(haloSigma)||haloSigma<0.25f||haloSigma>32.0f)return 0;
    try{
        auto& c=*static_cast<Context*>(p);
        if(!c.lightFields)c.lightFields=std::make_unique<LightFieldCache>();
        c.lightFields->compute(source,haloSigma,core,halo);
        return 1;
    }catch(...){
        // An allocation exception must never escape across the C/FFI boundary.
        return 0;
    }
}

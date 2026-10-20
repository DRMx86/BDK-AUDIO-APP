#pragma once
#include <array>
#include <cstdint>
#include "led_config.h"

// Memory-backed driver; integer color arithmetic matches the firmware.
struct RGB_SPI {
    uint8_t r = 0, g = 0, b = 0;
    RGB_SPI() = default;
    RGB_SPI(uint8_t red, uint8_t green, uint8_t blue) : r(red), g(green), b(blue) {}
    RGB_SPI scale(uint8_t v) const {
        return RGB_SPI((r*v+128)>>8, (g*v+128)>>8, (b*v+128)>>8);
    }
    static RGB_SPI fromHSV(uint8_t h, uint8_t s, uint8_t v) {
        if (!s) return RGB_SPI(v,v,v);
        uint8_t region=(h*6)>>8, remainder=(h*6)-(region<<8);
        uint8_t p=(v*(255-s)+128)>>8;
        uint8_t q=(v*(255-((s*remainder+128)>>8))+128)>>8;
        uint8_t t=(v*(255-((s*(255-remainder)+128)>>8))+128)>>8;
        switch(region) {
            case 0:return RGB_SPI(v,t,p);case 1:return RGB_SPI(q,v,p);
            case 2:return RGB_SPI(p,v,t);case 3:return RGB_SPI(p,q,v);
            case 4:return RGB_SPI(t,p,v);default:return RGB_SPI(v,p,q);
        }
    }
    RGB_SPI add(const RGB_SPI& o) const {
        return RGB_SPI(r+o.r>255?255:r+o.r,g+o.g>255?255:g+o.g,b+o.b>255?255:b+o.b);
    }
};
class LedDriverSPI {
public:
    void clear(){fill(RGB_SPI());}
    void fill(RGB_SPI c){pixels_.fill(c);}
    RGB_SPI getPixel(int i)const{return i>=0&&i<LED_MATRIX_COUNT?pixels_[i]:RGB_SPI();}
    void setPixel(int i,RGB_SPI c){if(i>=0&&i<LED_MATRIX_COUNT)pixels_[i]=c;}
    void setPixelXY(int x,int y,RGB_SPI c){
        if(x>=0&&x<16&&y>=0&&y<16)setPixel(index(x,y),c);
    }
    RGB_SPI getPixelXY(int x,int y)const{
        return x>=0&&x<16&&y>=0&&y<16?getPixel(index(x,y)):RGB_SPI();
    }
    void fadeAll(uint8_t s){for(auto& p:pixels_)p=p.scale(s);}
private:
    static int index(int x,int y){return y*16+((y&1)?15-x:x);}
    std::array<RGB_SPI,LED_MATRIX_COUNT> pixels_{};
};
namespace ColorsSPI {
    inline const RGB_SPI Black(0,0,0),White(255,255,255),Red(255,0,0),Green(0,255,0);
    inline const RGB_SPI Blue(0,0,255),Yellow(255,255,0),Cyan(0,255,255),Magenta(255,0,255);
    inline const RGB_SPI Orange(255,128,0),Purple(128,0,255);
}

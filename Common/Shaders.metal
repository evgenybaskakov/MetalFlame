/*
Copyright © 2017 Evgeny Baskakov. All Rights Reserved.
*/

#include <metal_stdlib>
#include <simd/simd.h>

//#define MAKING_ICON

using namespace metal;

constant float kPi = 3.14159265359;

#ifdef MAKING_ICON
constant int kSmoothUpwardsShift = 1;
#else
constant int kSmoothUpwardsShift = 2;
#endif

constant uint kSparkSparseness = 10000;
constant uint kSparkShakeSparseness = 70;
constant uint kSparkMinUpwardsSpeed = 2;
constant uint kSparkMaxUpwardsSpeed = 4;
constant uint kSparkCoolingSpeed = 1;

constant float kActivationCoolingRate = 10;

constant int kCellValueAlive = 255;
constant int kCellValueDead = 0;

constant float kStarEdgeSmooth = 1.5;

constant int kWarpBlockSize = 16;

constant float sqrt2 = 1.4142135;
constant float sqrt5 = 2.2360678;

constant float kNorms[][3] = {
    { 0.0,                   kWarpBlockSize,          kWarpBlockSize * 2.0 },
    { kWarpBlockSize,        kWarpBlockSize * sqrt2,  kWarpBlockSize * sqrt5 },
    { kWarpBlockSize * 2.0,  kWarpBlockSize * sqrt5,  kWarpBlockSize * 2.0 * sqrt2 }
};

typedef struct
{
    packed_float2 position;
    packed_float2 texCoords;
} VertexIn;

typedef struct {
    float4 position [[position]];
    float2 texCoords;
} FragmentVertex;

typedef struct {
    float ft;
    unsigned int frame;
    uint seed;
    bool warp;
    bool shake;
    bool persistentDraw;
} GameState;

typedef struct {
    float x, y, xv, yv;
} WarpOffset;

typedef struct {
    float x, y, xv, yv;
    float hot;
    float speed;
} Spark;

vertex FragmentVertex lighting_vertex(device VertexIn *vertexArray [[buffer(0)]],
                                      uint vertexIndex [[vertex_id]])
{
    FragmentVertex out;
    out.position = float4(vertexArray[vertexIndex].position, 0, 1);
    out.texCoords = vertexArray[vertexIndex].texCoords;
    return out;
}

fragment float4 lighting_fragment(FragmentVertex in [[stage_in]],
                                  texture2d<uint, access::sample> gameGrid [[texture(0)]],
                                  const device packed_float4 *colorMap [[buffer(0)]])
{
    constexpr sampler nearestSampler(coord::normalized, filter::nearest);
    ushort r = gameGrid.sample(nearestSampler, in.texCoords).r;
    float4 p = colorMap[r];
    p[3] = p[0]+p[1]+p[2];
    if(p[3] > 1.0) p[3] = 1.0;
    return p;
}

static device WarpOffset *offsetAt(device WarpOffset *offsets, ushort xo, ushort yo, ushort width)
{
    return &offsets[(width/kWarpBlockSize + 2) * yo + xo];
}

static ushort sparkAt(device ushort *spark_map, ushort x, ushort y, ushort width)
{
    return spark_map[width * y + x];
}

static void setSparkAt(device ushort *spark_map, ushort x, ushort y, ushort width, ushort hot)
{
    spark_map[width * y + x] = hot;
}

static float smooth_and_warp(texture2d<uint, access::sample> readTexture,
                             texture2d<uint, access::write> writeTexture,
                             device WarpOffset *offsets,
                             device ushort *coolmap,
                             device ushort *spark_map,
                             device ushort *pointBuffer,
                             ushort2 gridPosition,
                             ushort width,
                             ushort height,
                             bool warp,
                             bool persistentDraw,
                             uint frame)
{
    int tx, ty;
    
    if(warp) {
        int xo = gridPosition.x / kWarpBlockSize;
        int yo = gridPosition.y / kWarpBlockSize;
        
        int xi = xo * kWarpBlockSize;
        int yi = yo * kWarpBlockSize;
        
        int dx = gridPosition.x - xi;
        int dy = gridPosition.y - yi;
        
        float VLDx = (offsetAt(offsets, xo,   yo+1, width)->x - offsetAt(offsets, xo,   yo, width)->x) / (float)kWarpBlockSize;
        float VRDx = (offsetAt(offsets, xo+1, yo+1, width)->x - offsetAt(offsets, xo+1, yo, width)->x) / (float)kWarpBlockSize;
        float VLDy = (offsetAt(offsets, xo,   yo+1, width)->y - offsetAt(offsets, xo,   yo, width)->y) / (float)kWarpBlockSize;
        float VRDy = (offsetAt(offsets, xo+1, yo+1, width)->y - offsetAt(offsets, xo+1, yo, width)->y) / (float)kWarpBlockSize;
        
        float TX1 = offsetAt(offsets, xo, yo, width)->x + VLDx * dy;
        float TY1 = offsetAt(offsets, xo, yo, width)->y + VLDy * dy;
        float TX2 = offsetAt(offsets, xo+1, yo, width)->x + VRDx * dy;
        float TY2 = offsetAt(offsets, xo+1, yo, width)->y + VRDy * dy;
        
        float HDx = (TX2 - TX1) / kWarpBlockSize;
        float HDy = (TY2 - TY1) / kWarpBlockSize;
        
        tx = floor(TX1 + HDx * dx + 0.5);
        ty = floor(TY1 + HDy * dx + 0.5);
    }
    else {
        tx = gridPosition.x;
        ty = gridPosition.y;
    }

    float val = 0;
    
    for(int yi = ty-1; yi <= ty+1; yi++) {
        for(int xi = tx-1; xi <= tx+1; xi++) {
            if(xi != tx || yi != ty) {
                int2 neighbor;
                neighbor.x = xi;
                neighbor.y = yi + kSmoothUpwardsShift;
                val += readTexture.read(uint2(neighbor)).r;
            }
        }
    }
    
    val /= 8;

    val -= coolmap[((gridPosition.y + frame) * width + gridPosition.x) % (width * height)];
    if(val < 0)
        val = 0;
    
    uint spark = sparkAt(spark_map, gridPosition.x, gridPosition.y, width);

    if(spark != 0) {
        val += spark;
        
        if(val > kCellValueAlive) {
            val = kCellValueAlive;
        }
    }
 
    ushort activation = pointBuffer[gridPosition.y * width + gridPosition.x];
    
    if(activation > 0) {
        val += activation;

        if(val > kCellValueAlive) {
            val = kCellValueAlive;
        }
        
        if(!persistentDraw) {
            ushort d = activation >= kActivationCoolingRate ? activation - kActivationCoolingRate : 0;
            pointBuffer[gridPosition.y * width + gridPosition.x] = d;
        }
    }

    writeTexture.write((ushort)val, uint2(gridPosition));
    
    return val;
}

static void relaxOffsets(device WarpOffset *curOffsets,
                         device WarpOffset *newOffsets,
                         ushort2 gridPosition,
                         ushort width,
                         ushort height)
{
    uint x = gridPosition.x;
    uint y = gridPosition.y;
    
    uint start_y = 0, end_y = height / kWarpBlockSize;
    uint start_x = 0, end_x = width / kWarpBlockSize;
    
    if(x >= start_x && x <= end_x && y >= start_y && y <= end_y) {
        uint xh = (x < end_x ? x + 1 : x);
        uint xl = (x > 0 ? x - 1 : x);

        uint yh = (y < end_y? y + 1 : y);
        uint yl = (y > 0 ? y - 1 : y);

        device WarpOffset *oldCenter = offsetAt(curOffsets, x, y, width);
        device WarpOffset *center = offsetAt(newOffsets, x, y, width);
        
        *center = *oldCenter;

        for(uint yi = yl; yi <= yh; yi++) {
            for(uint xi = xl; xi <= xh; xi++) {
                if((xi != x) || (yi != y)) {
                    device WarpOffset *side = offsetAt(curOffsets, xi, yi, width);
                    float xspring = center->x - side->x;
                    float yspring = center->y - side->y;
                    float length = sqrt(xspring*xspring + yspring*yspring);
                    float norm = kNorms[xi >= x? xi-x : x-xi][yi >= y? yi-y : y-yi];
                    float diff = (norm - length) * 0.001;
                    xspring *= diff;
                    yspring *= diff;
                    center->xv += xspring;
                    center->yv += yspring;
                }
            }
        }

        // Adjust the warp, keeping the coordinates around the grid verfices, i.e.
        // keep x in [xi-1.0, xi+1.0], and y in [yi-1.0, y+1.0].
        // For that, map the accumulator to sinuse, by scaling it to PI/2 (which itself maps to 1.0).
        center->x = (x * kWarpBlockSize) + sin((center->x - (x * kWarpBlockSize) + center->xv) * (kPi / 2.0));
        center->y = (y * kWarpBlockSize) + sin((center->y - (y * kWarpBlockSize) + center->yv) * (kPi / 2.0));
    }
}

static void animate_sparks(ushort2 gridPosition,
                           ushort width,
                           device ushort *spark_map,
                           device Spark *sparks,
                           bool hotspot,
                           bool shake,
                           uint seed)
{
    uint i = gridPosition.y * width + gridPosition.x;
    
    device Spark *spark = &sparks[i];
    
    if(spark->hot > 0) {
        spark->x += spark->xv;
        spark->y += spark->yv - spark->speed;
        spark->xv *= 0.9;
        spark->yv *= 0.9;
        spark->hot -= kSparkCoolingSpeed * (spark->speed / kSparkMinUpwardsSpeed);
        
        if(spark->hot <= 0 ||
           spark->x < 0 ||
           spark->x >= width ||
           spark->y < 0)
        {
            spark->hot = 0;
        }
        else {
            uint x = floor(spark->x + 0.5);
            uint y = floor(spark->y + 0.5);
            
            setSparkAt(spark_map, x, y, width, spark->hot);
        }
    }
    else if(hotspot) {
        seed *= (i + 1);
        
        uint sparkSparseness = (shake ? kSparkShakeSparseness :kSparkSparseness);
        
        if(seed % sparkSparseness == 0) {
            const int dx = 3000;
            const int dy = 1000;
            const int dh = 100;
            
            spark->x = gridPosition.x;
            spark->y = gridPosition.y;
            spark->xv = (float)((int)(seed % dx) - dx/2) * 0.001;
            spark->yv = -((float)(seed % dy) * 0.001);
            spark->hot = kCellValueAlive - dh + seed % dh;
            spark->speed = kSparkMinUpwardsSpeed + (float)((seed + i) % ((kSparkMaxUpwardsSpeed - kSparkMinUpwardsSpeed + 1) * 100)) / 100.0;
        }
    }
}

kernel void game_of_life(texture2d<uint, access::sample> readTexture [[texture(0)]],
                         texture2d<uint, access::write> writeTexture [[texture(1)]],
                         sampler wrapSampler [[sampler(0)]],
                         ushort2 gridPosition [[thread_position_in_grid]],
                         constant GameState *state [[buffer(0)]],
                         device WarpOffset *curOffsets [[buffer(1)]],
                         device WarpOffset *newOffsets [[buffer(2)]],
                         device ushort *coolmap [[buffer(3)]],
                         device Spark *sparks [[buffer(4)]],
                         device ushort *spark_map_read [[buffer(5)]],
                         device ushort *spark_map_write [[buffer(6)]],
                         device ushort *pointBuffer [[buffer(7)]])
{
    ushort width = readTexture.get_width();
    ushort height = readTexture.get_height();
    writeTexture.write(kCellValueDead, uint2(gridPosition));
    
    if (gridPosition.x < width && gridPosition.y < height) {
        bool sparkHotspot = (pointBuffer[gridPosition.y * width + gridPosition.x] == kCellValueAlive ? true : false);

        float newPixel = smooth_and_warp(readTexture,
                                         writeTexture,
                                         curOffsets,
                                         coolmap,
                                         spark_map_read,
                                         pointBuffer,
                                         gridPosition,
                                         width,
                                         height,
                                         state->warp,
                                         state->persistentDraw,
                                         state->frame);
        
        if(state->warp) {
            relaxOffsets(curOffsets, newOffsets, gridPosition, width, height);
        }

        bool hotspot = false;
        if(!state->persistentDraw) {
            float x = gridPosition.x - width/2;
            float y = gridPosition.y - 3*height/4;
            
#ifdef MAKING_ICON
            float ang = kPi/2 - (kPi*2/5);
#else
            float ang = state->ft;
#endif
            
            float xr = x * cos(ang) - y * sin(ang);
            float yr = x * sin(ang) + y * cos(ang);
            
            float t = height/6 + height/16 * cos(5 * atan2(yr, xr));
            float val = sqrt(xr*xr + yr*yr) - abs(t);

#ifdef MAKING_ICON
            float thickness = 5;
#else
            float thickness = 1.63 * max(1.0, height / 667.0);
#endif
            
            hotspot = (abs(val) < thickness ? true : false);
            
            if(hotspot) {
                writeTexture.write(kCellValueAlive, uint2(gridPosition));
            }
            else {
                float d = abs(val) - thickness;
                
                if(d < kStarEdgeSmooth) {
                    float p = ((kStarEdgeSmooth - d) * kCellValueAlive) / kStarEdgeSmooth;
                    
                    if(p > newPixel) {
                        writeTexture.write((ushort)p, uint2(gridPosition));
                    }
                }
            }
        }
        
        animate_sparks(gridPosition, width, spark_map_write, sparks, hotspot || sparkHotspot, state->shake, state->seed);
    }
}

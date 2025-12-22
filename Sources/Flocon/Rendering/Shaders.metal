#include <metal_stdlib>
using namespace metal;

struct Frame { float2 extent; float time; float scale; };
struct Instance { float2 center; float size; float opacity; float4 color; float4 motion; };
struct MeshPoint { float2 point; float4 color; };
struct Pixel { float4 clip [[position]]; float2 local; float2 world; float4 color; float material; float phase; float time; float2 extra; };

static float4 project(float2 p, constant Frame &f) { return float4(2.0 * p / f.extent - 1.0, 0.0, 1.0); }

vertex Pixel flakeQuad(uint corner [[vertex_id]], uint instance [[instance_id]],
                       const device Instance *snow [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    constexpr float2 uv[6] = { {-1,-1}, {1,-1}, {-1,1}, {-1,1}, {1,-1}, {1,1} };
    Instance s = snow[instance];
    float2 local = uv[corner];
    float2 size = float2(s.size * 0.65);
    if (s.motion.z < 1.5) size.y += min(abs(s.motion.y) * 0.004, s.size * 0.4);
    float2 p = s.center + local * size;
    Pixel out;
    out.clip = project(p, f); out.local = local; out.world = p;
    out.color = float4(s.color.rgb, s.opacity); out.material = s.motion.z;
    out.phase = s.motion.w + f.time * (0.6 + fract(s.motion.w));
    out.time = f.time; out.extra = s.motion.xy;
    return out;
}
// Brightness of one bulb for a LightBlink pattern: 0 steady, 1 slow, 2 fast, 3 twinkle, 4 chase.
static float bulbLevel(int mode, float n, float t) {
    const float dim = 0.12;
    if (mode == 1 || mode == 2) {
        float rate = mode == 1 ? 1.6 : 5.0;
        return dim + (1.0 - dim) * smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(t * rate + fmod(n, 2.0) * M_PI_F));
    }
    if (mode == 3) {
        float r = fract(sin(n * 12.9898) * 43758.5453);
        return dim + (1.0 - dim) * pow(0.5 + 0.5 * sin(t * (1.2 + 2.0 * r) + r * 40.0), 2.0);
    }
    if (mode == 4) return dim + (1.0 - dim) * pow(0.5 + 0.5 * sin(t * 4.0 - n * 0.7), 3.0);
    return 1.0;
}
fragment float4 flakePixel(Pixel p [[stage_in]]) {
    float distance = length(p.local);
    if (p.material > 1.5) {
        float bulb = 1.0 - smoothstep(0.3, 0.58, length(p.local * float2(1.2, 1.0)));
        float halo = 0.10 * exp(-distance * 4.0);
        float a = (bulb + halo) * (0.94 + 0.06 * sin(p.phase)) * bulbLevel(int(p.extra.x + 0.5), p.extra.y, p.time);
        float3 color = mix(p.color.rgb, float3(1,0.98,0.88), 0.45 * exp(-distance * 9.0));
        return float4(color * a, a);
    }
    if (p.material > 0.5) distance *= 1.0 + 0.10 * sin(atan2(p.local.y,p.local.x) * 5.0 + p.phase);
    float a = (1.0 - smoothstep(0.25, 1.0, distance)) * p.color.a;
    float3 c = mix(float3(0.98,0.99,1), float3(0.76,0.83,0.92), saturate(p.local.y * -0.25 + 0.18));
    return float4(c * a, a);
}
vertex Pixel snowMesh(uint index [[vertex_id]], const device MeshPoint *mesh [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    MeshPoint v = mesh[index];
    Pixel p; p.clip = project(v.point, f); p.world = v.point; p.local = 0;
    p.color = v.color; p.material = 0; p.phase = 0; p.time = 0; p.extra = 0;
    return p;
}
fragment float4 snowPixel(Pixel p [[stage_in]], constant float4 *covers [[buffer(0)]], constant uint &count [[buffer(1)]]) {
    for (uint i = 0; i < count; ++i) {
        float4 r = covers[i];
        if (all(p.world >= r.xy) && all(p.world < r.zw)) discard_fragment();
    }
    return float4(p.color.rgb * p.color.a, p.color.a);
}
vertex float4 cableVertex(uint index [[vertex_id]], const device float2 *wire [[buffer(0)]], constant Frame &f [[buffer(1)]]) { return project(wire[index], f); }
fragment float4 cablePixel() { return float4(0.035, 0.10, 0.065, 0.8); }

#include <metal_graphics>
#include <metal_geometric>
#include <metal_texture>

using namespace metal;

struct VertexInOut
{
    float4 pos [[position]];
    float2 texCoord [[user(texturecoord)]];
};

vertex VertexInOut TexturedQuadVertex(constant float4         *pos        [[ buffer(0) ]],
        constant packed_float2  *texCoords  [[ buffer(1) ]],
        uint                     vid        [[ vertex_id ]])
{
VertexInOut outVertices;

outVertices.pos      = pos[vid];
outVertices.texCoord = texCoords[vid];

return outVertices;
}

fragment half4 TexturedQuadFragment(VertexInOut      inFrag    [[ stage_in ]],
texture2d<half>  tex2D     [[ texture(0) ]])
{
constexpr sampler quadSampler;
half4 color = tex2D.sample(quadSampler, inFrag.texCoord);

return color;
}
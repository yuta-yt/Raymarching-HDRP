#define PI2 (PI*2.0)
#define mod(x, y) ((x) - (y) * floor((x) / (y)))
#define rep(x, y) (mod(x - y*0.5, y) - y*0.5)

struct DistanceFunctionSurfaceData {
    float3 Position;
    float3 Normal;
    float3 BentNormal;

    float3 Albedo;
    float3 Emissive;
    float  Occlusion;
    float  Metallic;
    float  Smoothness;
};

DistanceFunctionSurfaceData initDistanceFunctionSurfaceData() {
    DistanceFunctionSurfaceData surface = (DistanceFunctionSurfaceData)0;
    surface.Albedo     = float3(1.0, 1.0, 1.0);
    surface.Occlusion  = 1.0;
    surface.Smoothness = 0.8;
    return surface;
}

float2x2 rot(in float a) {
    float s = sin(a), c = cos(a);
    return float2x2(c, s, -s, c);
}

float2 pmod(in float2 p, in float s) {
    float a = PI / s - atan2(p.x, p.y);
    float n = PI2 / s;
    a = floor(a / n) * n;
    return mul(rot(a), p);
}

float distanceFunction(float3 p, inout float m);
DistanceFunctionSurfaceData getDistanceFunctionSurfaceData(float3 p, float m);
void GetBuiltinData(FragInputs input, float3 V, inout PositionInputs posInput, SurfaceData surfaceData, float alpha, float3 bentNormalWS, float depthOffset, out BuiltinData builtinData);

float3 getObjectScale() {
    return float3(
        length(UNITY_MATRIX_M._11_21_31),
        length(UNITY_MATRIX_M._12_22_32),
        length(UNITY_MATRIX_M._13_23_33)
    );
}

float map(float3 p, inout float m) {
    // Ray overshoot at different scales depending on the axis.
    // Normalize the distance field with the smallest scale to prevent it.
    float3 scale = getObjectScale();
    return distanceFunction(TransformWorldToObject(p), m) /* * min(scale.x, min(scale.y, scale.z))*/;
}

float3 normal(float3 p, float eps) {
    // Calculate normal in object space and convert it to world space to reduce differences due to posture.
    p = TransformWorldToObject(p);
    float2 e = float2(1.0, -1.0) * eps;
    float m = 0;
    return TransformObjectToWorldDir(normalize(
        e.xyy * distanceFunction(p + e.xyy, m) +
        e.yxy * distanceFunction(p + e.yxy, m) +
        e.yyx * distanceFunction(p + e.yyx, m) +
        e.xxx * distanceFunction(p + e.xxx, m)
    ));
}

float ao(float3 p, float3 n, float dist) {
    float occ = 0.0;
    float m = 0.0;
    for (int i = 0; i < 16; ++i) {
        float h = 0.001 + dist*pow(float(i)/15.0,2.0);
        float oc = clamp(map( p + h*n , m)/h, -1.0, 1.0);
        occ += oc;
    }
    return occ / 16.0;
}

bool clipSphere(float3 p, float offset) {
    float d = length(TransformWorldToObject(p)) - (0.5 + offset);
    if (d < 0.0) {
        return false;
    } else {
        return true;
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
float3 GetRayOrigin(float3 positionRWS, bool isFrontFace)
{
    // If we're outside the mesh, start the ray on the mesh surface, otherwise use the camera position (origin)
    return isFrontFace ? positionRWS : float3(0.0, 0.0, 0.0);
}

float3 GetShadowRayOrigin(float3 positionRWS, bool isFrontFace)
{
    float3 viewPos = GetCurrentViewPosition();
    float3 pos = float3(0.0, 0.0, 0.0);

    if (IsPerspectiveProjection())
    {
        // Perspective(Point or Spot Light?)
        pos = viewPos;
    }
    else
    {
        // Orthographic(Directional Light?)
        // Directional Light cameras are always expected to be outside the meshDirectional light.
        pos = positionRWS;  // fix me?
    }

    return isFrontFace ? positionRWS : pos;
}

float TraceDepth(float3 ro, float3 ray, int ite, float epsBase) {
    float t = 0.0001;
    float3 p;
    float m = 0;
    for(int i = 0; i< ite; i++) {
        p = ro + ray * t;
        float d = map(p, m);
        t += d;
        if (d < t * epsBase) break;
    }
    if (clipSphere(p, 0.0)) {
        discard;
    }
    return t;
}

float TraceDF(float3 ro, float3 ray, int ite, float epsBase, inout float m) {
    float t = 0.0001;
    float3 p;
    for(int i = 0; i< ite; i++) {
        p = ro + ray * t;
        float d = map(p, m);
        t += d;
        if (d < t * epsBase) break;
    }
    if (clipSphere(p, 0.0)) {
        discard;
    }
    return t;
}

DistanceFunctionSurfaceData Trace(float3 ro, float3 ray, int ite, float epsBase) {
    float m = 0;
    float t = TraceDF(ro, ray, ite, epsBase, m);
    return getDistanceFunctionSurfaceData(ray * t + ro, m);
}

void ToHDRPSurfaceAndBuiltinData(FragInputs input, float3 V, inout PositionInputs posInput, DistanceFunctionSurfaceData surface, out SurfaceData surfaceData, out BuiltinData builtinData) {
    surfaceData = (SurfaceData)0;
    surfaceData.materialFeatures = MATERIALFEATUREFLAGS_LIT_STANDARD;
    surfaceData.normalWS = surface.Normal;
    surfaceData.ambientOcclusion = surface.Occlusion;
    surfaceData.perceptualSmoothness = surface.Smoothness;
    surfaceData.specularOcclusion = GetSpecularOcclusionFromAmbientOcclusion(ClampNdotV(dot(surfaceData.normalWS, V)), surfaceData.ambientOcclusion, PerceptualSmoothnessToRoughness(surfaceData.perceptualSmoothness));
    surfaceData.baseColor = surface.Albedo;
    surfaceData.metallic = surface.Metallic;
    input.positionRWS = surface.Position;
    posInput.positionWS = surface.Position;

    float alpha = 1.0;
#if HAVE_DECALS
    if (_EnableDecals)
    {
        DecalSurfaceData decalSurfaceData = GetDecalSurfaceData(posInput, alpha);
        ApplyDecalToSurfaceData(decalSurfaceData, surfaceData);
    }
#endif

    GetBuiltinData(input, V, posInput, surfaceData, alpha, surface.BentNormal, 0.0, builtinData);
    builtinData.emissiveColor = surface.Emissive;
}

float WorldPosToDeviceDepth(float3 p) {
    float4 device = TransformWorldToHClip(p);
    return device.z / device.w;
}
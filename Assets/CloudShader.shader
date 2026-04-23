Shader "Cloud"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            
            // To prevent crashing
            #define MIN_DENSITY_STEP_SIZE .2
            #define MAX_LIGHT_STEPS 16
            
            #pragma region Structs

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD1;
            };
            
            #pragma endregion 

            #pragma region Uniforms

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;
            
            float4 _Color;
            float4 _MainTex_ST; // Unity specific thing
            float3 _BoundsMin, _BoundsMax;
            
            // 3D Tex Sampling
            float _StepSize;
            Texture3D<float4> _3DTex;
            SamplerState sampler_3DTex;

            // Shape Settings
            float _DensityThreshold, _DensityMultiplier;
            float _CloudScale;
            float3 _CloudOffset;
            float _OffsetSpeed;

            // Lighting
            int _LightSteps;
            float _LightAbsorbtionTowardsSun, _DarknessThreshold;
            float _ForwardScatteringK, _BackwardsScatteringK, _BaseBrightness, _PhaseFactor;

            #pragma endregion
            
            #pragma region Helper Functions

            // Ray-Box intersection edited from: http://jcgt.org/published/0007/03/04/ 
            // Float[0] = Distance to start of box. Float[1] = Distance to back of box
            // (This article is simple but awesome, and might  be helpful for Tech Art)
            float2 rayBoxDist(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRaydir) {
                float3 t0 = (boundsMin - rayOrigin) * invRaydir;
                float3 t1 = (boundsMax - rayOrigin) * invRaydir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                float distToBox = max(0, dstA);
                float distInsideBox = max(0, dstB - distToBox);
                
                return float2(distToBox, distInsideBox);
            }

            /// <summary>
            /// The ever so mathful
            /// </summary>
            float henyeyGreenstein(float a, float g) {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(1+g2-2*g*(a), 1.5));
            }

            /// <summary>
            /// The phase function using HG
            /// </summary>
            float phase(float a) {
                float blend = .5;
                float hgBlend =
                    henyeyGreenstein(a,_ForwardScatteringK) * (1 - blend) +
                    henyeyGreenstein(a,-_BackwardsScatteringK) * blend;
                return _BaseBrightness + hgBlend * _PhaseFactor;
            }

            /// <summary>
            /// Returns density (red channel) of 3D Tex uniform, at Pos.
            /// </summary>
            float sampleDensity(float3 samplePos)
            {
                float3 uvw = samplePos * _CloudScale + (_CloudOffset * (_Time * _OffsetSpeed));
                float4 noise = _3DTex.SampleLevel(sampler_3DTex, uvw.xyz, 0.0f);
                float density = max(0, noise.r - _DensityThreshold) * _DensityMultiplier;
                return density;
            }

            /// <summary>
            /// Returns amount of light at pixel.
            /// Marches towards light, and towards viewer (forward scattering) <-- not done yet
            /// Used by densityRayMarch
            /// </summary>
            float lightRayMarch(float3 pos)
            {
                float3 dirToLight = _WorldSpaceLightPos0.xyz;
                float distInsideBox = rayBoxDist(_BoundsMin, _BoundsMax, pos, 1 / dirToLight).y;

                float stepSize = distInsideBox / _LightSteps;
                
                float totalDensity = 0;
                for (int step = 0; step < _LightSteps; step++)
                {
                    pos += dirToLight * stepSize;
                    
                    totalDensity += max(0, sampleDensity(pos) * stepSize);
                }
                float transmittance = exp(-totalDensity * _LightAbsorbtionTowardsSun);
                return _DarknessThreshold + transmittance * (1 - _DarknessThreshold);
            }
            
            /// <summary>
            /// Float[0] = Transmittance. Float[1] = Light Energy
            /// </summary>
            float2 densityRayMarch(float3 startPos, float3 dir, float distLimit, float stepSize, float phaseVal) {
                float transmittance = 1;
                float lightEnergy = 0;
                float dstTravelled = 0;
                
                while (dstTravelled < distLimit)
                {
                    float3 samplePosition = startPos + dir * dstTravelled;
                    float density = sampleDensity(samplePosition) * _StepSize;

                    if (density > 0)
                    {
                        float lightTransmittance = lightRayMarch(samplePosition);
                        lightEnergy += density * transmittance * _StepSize * lightTransmittance * phaseVal;

                        transmittance *= exp(-density * _StepSize);
                        
                        if (transmittance < .01f)
                            break;
                    }
                    
                    dstTravelled += _StepSize;
                }

                return float2(transmittance, lightEnergy);
            }

            #pragma endregion
            
            #pragma region Shaders
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                // Get screen
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                // Remap UVs [0,1] -> [-1,1]
                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                o.viewDir = mul(unity_CameraToWorld, float4(viewVector, 0));

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 bgClr = tex2D(_MainTex, i.uv);

                // Ray setup from camera
                float3 rayStart = _WorldSpaceCameraPos;
                float3 rayDir = normalize(i.viewDir);
                
                // Determine if Frag is in bounding box
                float2 rayBoxInfo = rayBoxDist(_BoundsMin, _BoundsMax, rayStart, 1/rayDir);
                float distToBox = rayBoxInfo.x;
                float distInsideBox = rayBoxInfo.y;
                
                // Don't over draw
                float depthLinear = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv)) * length(i.viewDir);
                
                bool rayInBounds = distInsideBox > 0 && distToBox < depthLinear;
                
                if(!rayInBounds)
                    return bgClr;


                // Phase Function calc
                float raySunAngle = dot(rayDir, _WorldSpaceLightPos0.xyz);
                float phaseVal = phase(raySunAngle);

                
                // Do the thing!
                float distLimit = min(depthLinear - distToBox, distInsideBox);
                float3 rayBoxEntryPos = rayStart + rayDir * distToBox;
                _StepSize = max(MIN_DENSITY_STEP_SIZE, _StepSize);
                _LightSteps = min(MAX_LIGHT_STEPS, _LightSteps);

                float2 rayMarchResults = densityRayMarch(rayBoxEntryPos, rayDir, distLimit, _StepSize, phaseVal);
                float transmittance = rayMarchResults.x;    // Beer-Lambert is accounted for
                float lightEnergy = rayMarchResults.y;      // 
                
                float4 cloudClr = lightEnergy * _Color;
                float3 clr = bgClr * transmittance + cloudClr;
                
                return float4(clr,1);
            }

            #pragma endregion
            
            ENDCG
        }
    }
}

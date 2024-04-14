Shader "Unlit/TestWaterRendering"
{
    Properties
    {
        //_MainTex ("Texture", 2D) = "white" {}
        _SunDirection("Light Dir", Vector)=(0,-1,0,1)
        _SunIrradiance("Sun Irradiance", Vector)=(0,-1,0,1)

        _FoamSubtract0("Foam Substract 0", vector)=(0,0,0,1)
        _FoamSubtract1("Foam Substract 1", vector)=(0,0,0,1)
        _FoamSubtract2("Foam Substract 2", vector)=(0,0,0,1)
        _FoamSubtract3("Foam Substract 3", vector)=(0,0,0,1)

        _NormalStrength("Normal Strength", Vector)=(0,0,0,1)
        _FoamDepthAttenuation("Foam Depth Attenuation", Vector)=(0,0,0,1)

        _NormalDepthAttenuation("Normals Depth Attenuation", Vector)=(0,0,0,1)

        _Roughness("Roughness", Float)=0.5
        _FoamRoughnessModifier("Foam Roughness Modifier", Float)=0.5

        _EnvironmentLightStrength("Environment Light Strength", Float)=0.5

        _HeightModifier("Height Modifier", Float)=0.5

        _ScatterColor("Scatter Color", Color)=(1,1,1,1)
        _BubbleColor("Bubble Color", Color)=(1,1,1,1)

        _WavePeakScatterStrength("Wave Peak Scatter Strength", Float)=0.5
        _ScatterStrength("Scatter Strength", Float)=0.5
        _ScatterShadowStrength("Scatter Shadow Strength", Float)=0.5

        _FoamColor("Foam Color", Color)=(1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {

            CGPROGRAM
            #pragma vertex vert
            #pragma hull hs
            #pragma domain ds
            #pragma geometry gs
            #pragma fragment frag
            //#include "UnityCG.cginc"

            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            // control point
            struct v2h{  
                float4 pos:SV_POSITION; 
                //float2 uv:TEXCOORD0;  // ??? is uv necessary or NOT ??? // chengzimdl 2024.04.10
            };

            #define _TessellationEdgeLength 10
            struct TessFactors {
                float edge[3] : SV_TESSFACTOR; // the bigger, the more tessellated triangles. =0, then culled at geometry shader.
                float inside : SV_INSIDETESSFACTOR;
            };

            bool TriangleIsBelowClipPlane(float3 p0, float3 p1, float3 p2, int planeIndex, float bias) {
                float4 plane = unity_CameraWorldClipPlanes[planeIndex];
                return dot(float4(p0, 1), plane) < bias && dot(float4(p1, 1), plane) < bias && dot(float4(p2, 1), plane) < bias;
            }

            bool cullTriangle(float3 p0, float3 p1, float3 p2, float bias) {
                return TriangleIsBelowClipPlane(p0, p1, p2, 0, bias) ||
                       TriangleIsBelowClipPlane(p0, p1, p2, 1, bias) ||
                       TriangleIsBelowClipPlane(p0, p1, p2, 2, bias) ||
                       TriangleIsBelowClipPlane(p0, p1, p2, 3, bias);
            }

            // Tess Factor depends on how much this patch occupies on the screen.
            float TessellationHeuristic(float3 cp0, float3 cp1) {
                float edgeLength = distance(cp0, cp1);
                float3 edgeCenter = (cp0 + cp1) * 0.5;
                float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

                return edgeLength * _ScreenParams.y / (_TessellationEdgeLength * (pow(viewDistance * 0.5f, 1.2f)));
            }

            TessFactors PatchFunction(InputPatch<v2h,3> input, uint i:SV_PRIMITIVEID){
                float3 p0=mul(unity_ObjectToWorld, input[0].pos);
                float3 p1=mul(unity_ObjectToWorld, input[1].pos);
                float3 p2=mul(unity_ObjectToWorld, input[2].pos);

                TessFactors f;
                float bias = -0.5 * 100;
                if (cullTriangle(p0, p1, p2, bias)) {
                    f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0;
                } else {
                    f.edge[0] = TessellationHeuristic(p1, p2);
                    f.edge[1] = TessellationHeuristic(p2, p0);
                    f.edge[2] = TessellationHeuristic(p0, p1);
                    f.inside = (TessellationHeuristic(p1, p2) +
                                TessellationHeuristic(p2, p0) +
                                TessellationHeuristic(p1, p2)) * (1 / 3.0);
                }
                return f;
            }

            struct d2g{
                float4 pos:SV_POSITION; 
            };

            /////////////////////////////////////////////////////////////////////////
            // introduce displacement texture array into final position
            UNITY_DECLARE_TEX2DARRAY(DisplacementTexture);
            UNITY_DECLARE_TEX2DARRAY(SlopeTexture);

            struct v2g{
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
				float depth : TEXCOORD2;
            };

            struct g2f{
                v2g data;  
                float3 bary:TEXCOORD10;
            };

            v2g vp(d2g v) {  
				v2g g;
                g.worldPos = mul(unity_ObjectToWorld, v.pos);

				// DX12 book: add offset to tessellated points, to make the plane to a real ocean surface.
                float3 displacement1 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 0.01f, 0), 0);
                float3 displacement2 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 3.0f, 1), 0);
                float3 displacement3 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 3.0f, 2), 0);
                float3 displacement4 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 0.13f, 3), 0);
				//float3 displacement = displacement1 + displacement2 + displacement3 + displacement4;
                float3 displacement = displacement1;
				

				float4 clipPos = UnityObjectToClipPos(v.pos);
				float depth = 1 - Linear01Depth(clipPos.z / clipPos.w); // linearization of depth

				displacement = lerp(0.0f, displacement, pow(saturate(depth), 1.0f)); // to make plane-point offsets related to depth.
																											  // i.e. related to the distance to camera/eye.

				v.pos.xyz += mul(unity_WorldToObject, displacement.xyz);  // original coord + offset
				
                g.pos = UnityObjectToClipPos(v.pos);
                g.uv = g.worldPos.xz;  // i.e. uv for texture sampling.
                g.worldPos = mul(unity_ObjectToWorld, v.pos);
				g.depth = depth;
				return g;
			}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            v2h vert (appdata v)
            {
                v2h o;
                o.pos=v.vertex;
                return o;
            }

            [domain("tri")]
            [partitioning("integer")]
            [outputtopology("triangle_cw")]
            [outputcontrolpoints(3)]
            [patchconstantfunc("PatchFunction")]
            v2h hs(InputPatch<v2h,3> patch, 
                   uint i:SV_OUTPUTCONTROLPOINTID){
                return patch[i];
            }

 

            // Here patch is OutputPatch, i.e. output of hull shader
            [domain("tri")]  // old return: d2g
            v2g ds(const OutputPatch<v2h,3> patch, TessFactors tf, float3 bary:SV_DOMAINLOCATION){ 
                d2g o; 
                o.pos=patch[0].pos*bary.x + patch[1].pos*bary.y + patch[2].pos*bary.z;
                return vp(o);
            }

            [maxvertexcount(3)]
            void gs(triangle v2g i[3], inout TriangleStream<g2f> stream){  // re-assign extreme values to each vertex of a triangle
                g2f o;
                o.data=i[0];
                o.bary=float3(1,0,0);
                stream.Append(o);

                o.data=i[1];
                o.bary=float3(0,1,0);
                stream.Append(o);

                o.data=i[2];
                o.bary=float3(0,0,1);
                stream.Append(o);
            }

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            #define PI 3.14159265358979323846

            float4 _SunDirection, _SunIrradiance, _FoamSubtract0, _FoamSubtract1, _FoamSubtract2, _FoamSubtract3, _NormalStrength, _FoamDepthAttenuation;
            float4 _NormalDepthAttenuation, _ScatterColor, _BubbleColor, _FoamColor;
            float _Roughness, _FoamRoughnessModifier, _EnvironmentLightStrength, _HeightModifier, _BubbleDensity;
            float _WavePeakScatterStrength, _ScatterStrength, _ScatterShadowStrength;
            

            samplerCUBE _EnvironmentMap;
			int _UseEnvironmentMap;

            float SmithMaskingBeckmann(float3 H, float3 S, float roughness) {	
				float hdots = max(0.001f, DotClamped(H, S));
				float a = hdots / (roughness * sqrt(1 - hdots * hdots));
				float a2 = a * a;
				return a < 1.6f ? (1.0f - 1.259f * a + 0.396f * a2) / (3.535f * a + 2.181 * a2) : 0.0f;
			}

            float Beckmann(float ndoth, float roughness) {  
				float exp_arg = (ndoth * ndoth - 1) / (roughness * roughness * ndoth * ndoth);
				return exp(exp_arg) / (PI * roughness * roughness * ndoth * ndoth * ndoth * ndoth);
			}

            float4 frag (g2f i) : SV_Target
            {
                float4 wireCol = float4(0,0,0,1);
                float4 baseCol = float4(1,1,1,1);

                float dist=min(min(i.bary.x, i.bary.y), i.bary.z);
                //return float4(lerp(wireCol, baseCol, dist).xyz, 1);

                float3 lightDir = -normalize(_SunDirection.xyz);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.data.worldPos);
                float3 halfwayDir = normalize(lightDir + viewDir);
			    float depth = i.data.depth;

                float4 displacementFoam1 = UNITY_SAMPLE_TEX2DARRAY(DisplacementTexture, float3(i.data.uv * 0.01f, 0));
				displacementFoam1.a += _FoamSubtract0;
                float4 displacementFoam2 = UNITY_SAMPLE_TEX2DARRAY(DisplacementTexture, float3(i.data.uv * 3.0f, 0));
				displacementFoam2.a += _FoamSubtract1;
                float4 displacementFoam3 = UNITY_SAMPLE_TEX2DARRAY(DisplacementTexture, float3(i.data.uv * 3.0f, 0));
				displacementFoam3.a += _FoamSubtract2;
                float4 displacementFoam4 = UNITY_SAMPLE_TEX2DARRAY(DisplacementTexture, float3(i.data.uv * 0.13f, 0));
				displacementFoam4.a += _FoamSubtract3;
                float4 displacementFoam = displacementFoam1 + displacementFoam2 + displacementFoam3 + displacementFoam4;

                float2 slopes1 = UNITY_SAMPLE_TEX2DARRAY(SlopeTexture, float3(i.data.uv * 0.01f, 0));
				float2 slopes2 = UNITY_SAMPLE_TEX2DARRAY(SlopeTexture, float3(i.data.uv * 3.0f, 1));
				float2 slopes3 = UNITY_SAMPLE_TEX2DARRAY(SlopeTexture, float3(i.data.uv * 3.0f, 2));
				float2 slopes4 = UNITY_SAMPLE_TEX2DARRAY(SlopeTexture, float3(i.data.uv * 0.13f, 3));
				float2 slopes = slopes1 + slopes2 + slopes3 + slopes4;

                slopes *=_NormalStrength;
				float foam = lerp(0.0f, saturate(displacementFoam.a), pow(depth, _FoamDepthAttenuation));

                float3 macroNormal = float3(0, 1, 0);  // normal of XOZ-plane
				float3 mesoNormal = normalize(float3(-slopes.x, 1.0f, -slopes.y));
                mesoNormal = normalize(lerp(float3(0, 1, 0), mesoNormal, pow(saturate(depth), _NormalDepthAttenuation)));  
				mesoNormal = normalize(UnityObjectToWorldNormal(normalize(mesoNormal)));

                float NdotL = DotClamped(mesoNormal, lightDir);  

                float a = _Roughness + foam * _FoamRoughnessModifier;
				float ndoth = max(0.0001f, dot(mesoNormal, halfwayDir));

				float viewMask = SmithMaskingBeckmann(halfwayDir, viewDir, a);
				float lightMask = SmithMaskingBeckmann(halfwayDir, lightDir, a);

                float G = rcp(1 + viewMask + lightMask);

                float eta = 1.33f;	// refraction of the ocean; air: 1
				float R = ((eta - 1) * (eta - 1)) / ((eta + 1) * (eta + 1));  // R0 = (n1-n2)^2 / (n1+n2)^2
				float thetaV = acos(viewDir.y); // draw a figure: viewDir.y is actually the projection onto surface normal, i.e. cos<n, viewDir>.
												// thus we can compute the angle between surface normal and viewDir.
				float numerator = pow(1 - dot(mesoNormal, viewDir), 5 * exp(-2.69 * a));  // what is the exp(...) ? which algorithm ?
				float F = R + (1 - R) * numerator / (1.0f + 22.7f * pow(a, 1.5f));  // ???
				F = saturate(F);

                float3 specular = _SunIrradiance.xyz * F * G * Beckmann(ndoth, a);
				specular /= 4.0f * max(0.001f, DotClamped(macroNormal, lightDir));
				specular *= DotClamped(mesoNormal, lightDir);

				float3 envReflection = texCUBE(_EnvironmentMap, reflect(-viewDir, mesoNormal)).rgb;
				envReflection *= _EnvironmentLightStrength;

				float H = max(0.0f, displacementFoam.y) * _HeightModifier;
				float3 scatterColor = _ScatterColor;
				float3 bubbleColor = _BubbleColor;
				float bubbleDensity = _BubbleDensity;
				
				float k1 = _WavePeakScatterStrength * H * pow(DotClamped(lightDir, -viewDir), 4.0f) * pow(0.5f - 0.5f * dot(lightDir, mesoNormal), 3.0f);
				float k2 = _ScatterStrength * pow(DotClamped(viewDir, mesoNormal), 2.0f);
				float k3 = _ScatterShadowStrength * NdotL;
				float k4 = bubbleDensity;

				float3 scatter = (k1 + k2) * scatterColor * _SunIrradiance * rcp(1 + lightMask);
				scatter += k3 * scatterColor * _SunIrradiance + k4 * bubbleColor * _SunIrradiance;

				float3 output = (1 - F) * scatter + specular + F * envReflection;  // diffuse + specular + ambient ???
				output = max(0.0f, output);
				output = lerp(output, _FoamColor, saturate(foam));
                return float4(output, 1.0f);
            }
            ENDCG
        }
    }
}

Shader "Unlit/TestWaterRendering"
{
    Properties
    {
        //_MainTex ("Texture", 2D) = "white" {}
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
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            // control point
            struct v2h{  
                float4 pos:SV_POSITION; 
                float2 uv:TEXCOORD0;  // ??? is uv necessary or NOT ??? // chengzimdl 2024.04.10
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



            //sampler2D _MainTex;
            //float4 _MainTex_ST;


            /////////////////////////////////////////////////////////////////////////
            // introduce displacement texture array into final position
            UNITY_DECLARE_TEX2DARRAY(DisplacementTexture);

            struct v2g{
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
				float depth : TEXCOORD2;
            };

            struct g2f{
                v2g data;  // chengzimdl 2024.04.10
                //float4 pos:SV_POSITION;   // chengzimdl 2024.04.10
                float3 bary:TEXCOORD10;
                float2 barycentricCoordinates : TEXCOORD9;   // chengzimdl 2024.04.10
                // is the 2D bary necessary ???
            };

            v2g vp(/*d2g v*/ appdata v) {  
				v2g g;
				//v.uv = 0;
                //g.worldPos = mul(unity_ObjectToWorld, v.pos);
                g.worldPos = mul(unity_ObjectToWorld, v.vertex);

				// DX12 book: add offset to tessellated points, to make the plane to a real ocean surface.
                float3 displacement1 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 0.01f, 0), 0);
                float3 displacement2 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 3.0f, 1), 0);
                float3 displacement3 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 3.0f, 2), 0);
                float3 displacement4 = UNITY_SAMPLE_TEX2DARRAY_LOD(DisplacementTexture, float3(g.worldPos.xz * 0.13f, 3), 0);
				//float3 displacement = displacement1 + displacement2 + displacement3 + displacement4;
                float3 displacement = displacement1;
				

				//float4 clipPos = UnityObjectToClipPos(v.pos);
                float4 clipPos = UnityObjectToClipPos(v.vertex);
				float depth = 1 - Linear01Depth(clipPos.z / clipPos.w); // linearization of depth

				displacement = lerp(0.0f, displacement, pow(saturate(depth), 1.0f)); // to make plane-point offsets related to depth.
																											  // i.e. related to the distance to camera/eye.

				//v.pos.xyz += mul(unity_WorldToObject, displacement.xyz);  // original coord + offset
                v.vertex += mul(unity_WorldToObject, displacement.xyz);  // original coord + offset
				
                //g.pos = UnityObjectToClipPos(v.pos);
                g.pos = UnityObjectToClipPos(v.vertex);
                g.uv = g.worldPos.xz;  // i.e. uv for texture sampling.
                //g.worldPos = mul(unity_ObjectToWorld, v.pos);
                g.worldPos = mul(unity_ObjectToWorld, v.vertex);
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
            //v2g ds(const OutputPatch<v2h,3> patch, TessFactors tf, float3 bary:SV_DOMAINLOCATION){ 
            v2g ds(OutputPatch<v2h,3> patch, TessFactors tf, float3 bary:SV_DOMAINLOCATION){ 
                //d2g o; 
                //o.pos=patch[0].pos*bary.x + patch[1].pos*bary.y + patch[2].pos*bary.z;
                //return vp(o);
                appdata data;
                data.vertex=patch[0].pos*bary.x+patch[1].pos*bary.y+patch[2].pos*bary.z;
                data.uv=patch[0].uv*bary.x+patch[1].uv*bary.y+patch[2].uv*bary.z;
                return vp(data);
            }

            [maxvertexcount(3)]
            void gs(triangle /*d2g*/ v2g i[3], inout TriangleStream<g2f> stream){  // re-assign extreme values to each vertex of a triangle
                //g2f o;
                ////o.pos=i[0].pos;  // chengzimdl 2024.04.10
                //o.data=i[0];
                //o.bary=float3(1,0,0);
                //o.barycentricCoordinates = float2(1, 0);  // chengzimdl 2024.04.10
                //stream.Append(o);

                
                ////o.pos=i[1].pos;
                //o.data=i[1];
                //o.bary=float3(0,1,0);
                //o.barycentricCoordinates = float2(0, 1);
                //stream.Append(o);

                ////o.pos=i[2].pos;
                //o.data=i[2];
                //o.bary=float3(0,0,1);
                //o.barycentricCoordinates = float2(0, 0);
                //stream.Append(o);

                g2f g0, g1, g2;
                g0.data = i[0];
                g1.data = i[1];
                g2.data = i[2];


                g0.barycentricCoordinates = float2(1, 0);
                g1.barycentricCoordinates = float2(0, 1);
                g2.barycentricCoordinates = float2(0, 0);


				g0.bary=float3(1,0,0);
				g1.bary=float3(0,1,0);
				g2.bary=float3(0,0,1);
				

                stream.Append(g0);
                stream.Append(g1);
                stream.Append(g2);
            }


            fixed4 frag (g2f i) : SV_Target
            {
                float4 wireCol = float4(0,0,0,1);
                float4 baseCol = float4(1,1,1,1);

                float dist=min(min(i.bary.x, i.bary.y), i.bary.z);
                return float4(lerp(wireCol, baseCol, dist).xyz, 1);
            }
            ENDCG
        }
    }
}

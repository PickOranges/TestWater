Shader "Unlit/TestWaterRendering"
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
            #pragma hull hs
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            // control point
            struct v2h{  
                float4 pos:SV_POSITION; 
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

            TessFactors PatchFunction(v2h input){
                float3 p0=mul(unity_ObjectToWorld, input.pos);
                float3 p1=mul(unity_ObjectToWorld, input.pos);
                float3 p2=mul(unity_ObjectToWorld, input.pos);

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

            sampler2D _MainTex;
            float4 _MainTex_ST;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            v2h vert (appdata v)
            {
                v2h o;
                o.pos = UnityObjectToClipPos(v.vertex);
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
            [domain("tri")]
            d2g ds(const OutputPatch<v2h,3> patch, TessFactors tf, float2 uv:SV_DOMAINLOCATION){ 
                float3 v1=lerp(patch[0].pos, patch[1].pos, uv.x);
                float3 v2=lerp(patch[0].pos, patch[2].pos, uv.x);
                float3 p=lerp(v1,v2, uv.y);
                p.y=0.3f*( p.z*sin(p.x) * p.x*cos(p.z) );

                d2g o;
                o.pos=float4(p,1.0f);
                o.pos = UnityObjectToClipPos(o.pos);
                return o;
            }

            fixed4 frag (d2g i) : SV_Target
            {
                //fixed4 col = tex2D(_MainTex, i.uv);
                fixed4 col = i.pos;
               
                return col;
            }
            ENDCG
        }
    }
}

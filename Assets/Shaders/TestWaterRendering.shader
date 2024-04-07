Shader "Unlit/TestWaterRendering"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        //DisplacementTexture ("DisplacementTexture", 2D)="white"{}
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

            //struct v2f
            //{
            //    float2 uv : TEXCOORD0;
            //    UNITY_FOG_COORDS(1)
            //    float4 vertex : SV_POSITION;
            //};

            // control point
            struct v2h{  
                float4 pos:SV_POSITION; 
                //float2 uv:TEXCOORD0;  // ??? is uv necessary or NOT ???
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

            struct g2f{
                float4 pos:SV_POSITION; 
                float3 bary:TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            //sampler2D DisplacementTexture;
            //float4 _Displacement_ST;
            //UNITY_DECLARE_TEX2D(DisplacementTexture);

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


            ////////////chengzimdl 2024.04.06 helper, called at the end of domain shader////////////
            //float4 vertexAddDisplacement(float4 i){
            //    float4 wPos=mul(unity_ObjectToWorld, i);
            //    float4 h=UNITY_SAMPLE_TEX2D(DisplacementTexture, wPos.xz * 0.01);

            //    d2g o;
            //    o.pos=i+h;


            //    o.pos=UnityObjectToClipPos(o.pos);


            //    return o.pos;
            //}

            // Here patch is OutputPatch, i.e. output of hull shader
            [domain("tri")]
            d2g ds(const OutputPatch<v2h,3> patch, TessFactors tf, float3 bary:SV_DOMAINLOCATION){ 
                d2g o;
                o.pos=patch[0].pos*bary.x + patch[1].pos*bary.y + patch[2].pos*bary.z;
                // TODO: do the same to bary coord. ?? or necessary??

                //o.pos=UnityObjectToClipPos(o.pos);  // 2024.04.07
                return o;
            }

            [maxvertexcount(3)]
            void gs(triangle d2g i[3], inout TriangleStream<g2f> stream){  // re-assign extreme values to each vertex of a triangle
                g2f o;
                o.pos=i[0].pos;
                o.bary=float3(1,0,0);
                stream.Append(o);

                o.pos=i[1].pos;
                o.bary=float3(0,1,0);
                stream.Append(o);

                o.pos=i[2].pos;
                o.bary=float3(0,0,1);
                stream.Append(o);
            }


            fixed4 frag (g2f i) : SV_Target
            {
                //fixed4 col = tex2D(_MainTex, i.uv);
                //fixed4 col = fixed4(i.pos);
                //return col;
                //return float4(1.0, 0.0, 0.0, 0.0);

                //float4 wPos=mul(unity_ObjectToWorld, i.pos);
                //float4 h=UNITY_SAMPLE_TEX2D(DisplacementTexture, wPos.xz * 0.01);
                //i.pos+=h;
                //i.pos=UnityObjectToClipPos(i.pos);

                float4 wireCol = float4(0,0,0,1);
                float4 baseCol = float4(1,1,1,1);

                float dist=min(min(i.bary.x, i.bary.y), i.bary.z);
                return float4(lerp(wireCol, baseCol, dist).xyz, 1);
            }
            ENDCG
        }
    }
}

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
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

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

            struct v2h{
                float4 vertex:SV_POSITION;
                float4 pos_WS;
                float4 depth;
                float2 uv:TEXCOORD0;
            };

            struct h2t{
                
            };

            struct HS_PATCH_CONST_DATA_OUTPUT{

            };

            HS_PATCH_CONST_DATA_OUTPUT PatchFunction(){
            
            }

            sampler2D _MainTex;
            float4 _MainTex_ST;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            [domain("tri")]
            [partitioning("integer")]
            [outputtopology("triangle_cw")]
            [outputcontrolpoints(32)]
            [patchconstfunc("PatchFunction")]
            h2t hull(v2h input, 
                    InputPatch<HS_PATCH_CONST_DATA_OUTPUT,3> patch, 
                    uint i:SV_OUTPUTCONTROLPOINTID, 
                    uint PatchID:SV_PRIMITIVEID){
            
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
               
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}

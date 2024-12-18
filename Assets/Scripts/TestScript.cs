using System;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;


public class TestScript : MonoBehaviour
{
    public ComputeShader waterFFTShader;
    public Shader waterRenderingShader;

    Camera _camera;
    public RenderTexture target;
    public RenderTexture _initSpectrum, _spectrum, _displacement, _slope; 

    Mesh mesh;
    Material material;
    Vector3[] verts;
    int[] tris;
    Vector3[] normals;
    float g = 9.81f;
    ComputeBuffer spectrumParamsBuffer;

    private int N, logN, threadGroupsX, threadGroupsY;

    public struct SpectrumSettings
    {
        public float scale;
        public float angle;
        public float spreadBlend;
        public float swell;
        public float alpha;
        public float peakOmega;
        public float gamma;
        public float shortWavesFade;
        // new
        //public float windSpeed;
    }
    SpectrumSettings[] spectrums = new SpectrumSettings[8];

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    [Header("Spectrum Settings")]
    [Range(0.0f, 0.1f)]
    public float lowCutoff = 0.0001f;
    [Range(0.1f, 9000.0f)]
    public float highCutoff = 9000.0f;
    [Range(2.0f, 20.0f)]
    public float depth = 20.0f;
    [Range(0.0f, 200.0f)]
    public float repeatTime = 200.0f;
    [Range(0.0f, 5.0f)]
    public float speed = 1.0f;
    public Vector2 lambda = new Vector2(1.0f, 1.0f);
    [Range(0.0f, 10.0f)]
    public float displacementDepthFalloff = 1.0f;
    public bool updateSpectrum = false;

    [Header("Layer One")]
    [Range(0, 2048)]
    public int lengthScale1 = 256;

    [Header("Layer Two")]
    [Range(0, 2048)]
    public int lengthScale2 = 256;

    [Header("Layer Three")]
    [Range(0, 2048)]
    public int lengthScale3 = 256;

    [Header("Layer Four")]
    [Range(0, 2048)]
    public int lengthScale4 = 256;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    [System.Serializable]
    public struct DisplaySpectrumSettings
    {
        [Range(0, 5)]
        public float scale;
        public float windSpeed;
        [Range(0.0f, 360.0f)]
        public float windDirection;
        public float fetch;
        [Range(0, 1)]
        public float spreadBlend;
        [Range(0, 1)]
        public float swell;
        public float peakEnhancement;
        public float shortWavesFade;
    }

    [SerializeField]
    public DisplaySpectrumSettings spectrum1;
    [SerializeField]
    public DisplaySpectrumSettings spectrum2;
    [SerializeField]
    public DisplaySpectrumSettings spectrum3;
    [SerializeField]
    public DisplaySpectrumSettings spectrum4;
    [SerializeField]
    public DisplaySpectrumSettings spectrum5;
    [SerializeField]
    public DisplaySpectrumSettings spectrum6;
    [SerializeField]
    public DisplaySpectrumSettings spectrum7;
    [SerializeField]
    public DisplaySpectrumSettings spectrum8;
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    [Header("Light Settings")]
    public float4 sunDirection;
    [ColorUsage(true, true)] public Color sunIrradiance;

    [Header("Normal Settings")]
    public float normalStrength = 1;
    public float normalDepthAttenuation = 1;

    [Header("Foam Settings")]
    [Range(-2.0f, 2.0f)]
    public float foamBias = -0.5f;
    [Range(-10.0f, 10.0f)]
    public float foamThreshold = 0.0f;
    [Range(0.0f, 1.0f)]
    public float foamAdd = 0.5f;
    [Range(0.0f, 1.0f)]
    public float foamDecayRate = 0.05f;
    [Range(0.0f, 1.0f)]
    public float bubbleDensity = 0.05f;
    [Range(-2.0f, 2.0f)] public float foamSubtract0;
    [Range(-2.0f, 2.0f)] public float foamSubtract1;
    [Range(-2.0f, 2.0f)] public float foamSubtract2;
    [Range(-2.0f, 2.0f)] public float foamSubtract3;
    [Range(0.0f, 2.0f)] public float roughness;
    [ColorUsage(true, true)] public Color foamColor;
    [Range(0.0f, 2.0f)] public float foamRoughnessModifier;
    [Range(0.0f, 10.0f)] public float foamDepthAttenuation;

    [Header("PBR Settings")]
    [ColorUsage(true, true)] public Color scatterColor;
    [ColorUsage(true, true)] public Color bubbleColor;
    [Range(0.0f, 2.0f)] public float environmentLightStrength;
    [Range(0.0f, 10.0f)] public float wavePeakScatterStrength;
    [Range(0.0f, 10.0f)] public float heightModifier;
    [Range(0.0f, 10.0f)] public float scatterStrength;
    [Range(0.0f, 10.0f)] public float scatterShadowStrength;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    void InitRenderTexture(RenderTexture rt)
    {
        if (!rt || rt.width != Screen.width || rt.height != Screen.height)
        {
            if (rt) rt.Release();
            rt = new RenderTexture(Screen.width, Screen.height, 0,
                RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
            rt.enableRandomWrite = true;
            rt.Create();
        }
    }
    // single texture
    RenderTexture CreateRenderTex(int width, int height, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.useMipMap = useMips;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 16;
        rt.Create();
        return rt;
    }

    // texture array
    RenderTexture CreateRenderTex(int width, int height, int depth, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.dimension = UnityEngine.Rendering.TextureDimension.Tex2DArray; 
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.volumeDepth = depth; // Number of elements in a texture array(Read Only), i.e. #Tex in this array.
        rt.useMipMap = useMips;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 16;
        rt.Create();
        return rt;
    }

    // ??? which one/what kind of data types should be released explicitly
    private void OnDestroy()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;
        spectrumParamsBuffer.Release();
    }

    void CreatePlane()
    {
        GetComponent<MeshFilter>().mesh = mesh = new Mesh();
        mesh.name = "WaterPlane";
        mesh.indexFormat = IndexFormat.UInt32;
        
        int length = 100;
        float halfL = length * 0.5f;
        int res = 2;
        int sideCnt = length * res;
        int num_vert = sideCnt * sideCnt;
        verts = new Vector3[(sideCnt+1)*(sideCnt+1)];  // +1 to avoid triangle idx access the vertex index that goes out of bound.

        Vector2[] uv = new Vector2[verts.Length];
        Vector4[] tangents = new Vector4[verts.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);
        
        
        // fill verts
        float deltaLength=(float)length/sideCnt;
        for(int i=0, x=0; x<=sideCnt; ++x)
        {
            for (int z=0; z<=sideCnt; ++z, ++i){
                verts[i] = new Vector3( (float)x*deltaLength-halfL, 0, (float)z*deltaLength - halfL);  // init vert coordinates, later vert.y will be replaced with the real height.
                uv[i] = new Vector2((float)x / sideCnt, (float)z / sideCnt);
                tangents[i] = tangent;
            }
        }

        mesh.vertices = verts;
        mesh.uv = uv;
        mesh.tangents = tangents;

        // fill tris
        tris = new int[num_vert * 6];
        for (int vi=0, ti=0, x=0; x<sideCnt; ++vi, ++x)
        {
            for(int z=0; z<sideCnt; ti+=6, ++z, ++vi)
            {
                tris[ti] = vi;
                tris[ti+1] = vi + 1;
                tris[ti+2] = vi + 2 + sideCnt;

                tris[ti+3] = vi;
                tris[ti+4] = vi + sideCnt + 2;
                tris[ti+5] = vi + sideCnt + 1;
            }
        }

        
        mesh.triangles = tris;
        mesh.RecalculateNormals();
        normals =mesh.normals; 
    }

    void CreateMaterial()
    {
        if (waterRenderingShader == null) return;
        material = new Material(waterRenderingShader);

        GetComponent<MeshRenderer>().material = material;
    }

    float JonswapAlpha(float fetch, float windSpeed)
    {
        return 0.076f * Mathf.Pow(g * fetch / (windSpeed * windSpeed), -0.22f);
    }

    float JonswapPeakFrequency(float fetch, float windSpeed)
    {
        return 22 * Mathf.Pow(windSpeed * fetch / (g * g), -0.33f);
    }

    void FillSpectrumStruct(DisplaySpectrumSettings displaySettings, ref SpectrumSettings computeSettings)
    {
        computeSettings.scale = displaySettings.scale;
        computeSettings.angle = displaySettings.windDirection / 180 * Mathf.PI;
        computeSettings.spreadBlend = displaySettings.spreadBlend;
        computeSettings.swell = Mathf.Clamp(displaySettings.swell, 0.01f, 1);
        computeSettings.alpha = JonswapAlpha(displaySettings.fetch, displaySettings.windSpeed);
        computeSettings.peakOmega = JonswapPeakFrequency(displaySettings.fetch, displaySettings.windSpeed);
        computeSettings.gamma = displaySettings.peakEnhancement;
        computeSettings.shortWavesFade = displaySettings.shortWavesFade;

        // new
        //computeSettings.windSpeed = displaySettings.windSpeed;
    }

    void SetSpectrumBuffers()
    {
        FillSpectrumStruct(spectrum1, ref spectrums[0]);
        FillSpectrumStruct(spectrum2, ref spectrums[1]);
        FillSpectrumStruct(spectrum3, ref spectrums[2]);
        FillSpectrumStruct(spectrum4, ref spectrums[3]);
        FillSpectrumStruct(spectrum5, ref spectrums[4]);
        FillSpectrumStruct(spectrum6, ref spectrums[5]);
        FillSpectrumStruct(spectrum7, ref spectrums[6]);
        FillSpectrumStruct(spectrum8, ref spectrums[7]);

        spectrumParamsBuffer.SetData(spectrums);
        waterFFTShader.SetBuffer(0, "Sps", spectrumParamsBuffer);
    }

    void SetFFTUniforms()
    {
        waterFFTShader.SetVector("_Lambda", lambda);
        waterFFTShader.SetFloat("_FrameTime", Time.time * speed);
        waterFFTShader.SetFloat("_RepeatTime", repeatTime);
        waterFFTShader.SetInt("N", N);
        waterFFTShader.SetFloat("D", depth);
        waterFFTShader.SetFloat("_LowCutoff", lowCutoff);
        waterFFTShader.SetFloat("_HighCutoff", highCutoff);


        waterFFTShader.SetInt("_LengthScale0", lengthScale1);
        waterFFTShader.SetInt("_LengthScale1", lengthScale2);
        waterFFTShader.SetInt("_LengthScale2", lengthScale3);
        waterFFTShader.SetInt("_LengthScale3", lengthScale4);


        waterFFTShader.SetFloat("_FoamThreshold", foamThreshold);
        waterFFTShader.SetFloat("_FoamBias", foamBias);
        waterFFTShader.SetFloat("_FoamDecayRate", foamDecayRate);
        waterFFTShader.SetFloat("_FoamAdd", foamAdd);
    }

    void InverseFFT(RenderTexture spectrumTexture)
    {
        waterFFTShader.SetTexture(3, "IFFTResult", spectrumTexture);
        //waterFFTShader.SetTexture(3, "target", target);
        waterFFTShader.Dispatch(3, 1, N, 1);
        waterFFTShader.SetTexture(4, "IFFTResult", spectrumTexture);
        //waterFFTShader.SetTexture(4, "target", target);
        waterFFTShader.Dispatch(4, 1, N, 1);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    void OnEndCameraRendering(ScriptableRenderContext context, Camera camera)
    {
        //if (!_target)
        //{
        //    Debug.Log("RenderTexture is empty.");
        //    return;
        //}
        //Graphics.Blit(_target, camera.targetTexture);
        //Graphics.CopyTexture(_target, camera.targetTexture);

        if (!target) return;
        Graphics.Blit(target, camera.targetTexture);
    }

    private void Start()
    {
        CreatePlane();
        CreateMaterial();
        _camera = Camera.main;

        N = 1024;
        logN = (int)Mathf.Log(N, 2.0f);
        threadGroupsX = Mathf.CeilToInt(N / 8.0f);
        threadGroupsY = Mathf.CeilToInt(N / 8.0f);

        // 1. Create Textures
        target = CreateRenderTex(N, N, RenderTextureFormat.ARGBHalf, true);
        
        _initSpectrum = CreateRenderTex(N, N, 4, RenderTextureFormat.ARGBHalf, true);
        _spectrum = CreateRenderTex(N, N, 8, RenderTextureFormat.ARGBHalf, true);

        _displacement = CreateRenderTex(N, N, 4, RenderTextureFormat.ARGBHalf, true);
        _slope = CreateRenderTex(N, N, 4, RenderTextureFormat.RGHalf, true);

        spectrumParamsBuffer = new ComputeBuffer(8, 8 * sizeof(float));
        SetSpectrumBuffers();
        SetFFTUniforms();

        // 2. Set Data & Dispatch
        waterFFTShader.SetTexture(0, "InitSpectrumTexture", _initSpectrum);
        waterFFTShader.SetTexture(0, "target", target);
        waterFFTShader.Dispatch(0, threadGroupsX, threadGroupsY, 1);
        waterFFTShader.SetTexture(1, "InitSpectrumTexture", _initSpectrum);
        //waterFFTShader.SetTexture(1, "target", target);
        waterFFTShader.Dispatch(1, threadGroupsX, threadGroupsY, 1);
    }

    private void Update()
    {
        // Debugging
        //RenderPipelineManager.endCameraRendering += OnEndCameraRendering;

        material.SetVector("_SunIrradiance", sunIrradiance);
        material.SetVector("_SunDirection", sunDirection);

        material.SetVector("_ScatterColor", scatterColor);
        material.SetVector("_BubbleColor", bubbleColor);
        material.SetVector("_FoamColor", foamColor);

        material.SetFloat("_FoamSubtract0", foamSubtract0);
        material.SetFloat("_FoamSubtract1", foamSubtract1);
        material.SetFloat("_FoamSubtract2", foamSubtract2);
        material.SetFloat("_FoamSubtract3", foamSubtract3);

        material.SetFloat("_Roughness", roughness);
        material.SetFloat("_FoamRoughnessModifier", foamRoughnessModifier);
        material.SetFloat("_NormalDepthAttenuation", normalDepthAttenuation);

        material.SetFloat("_EnvironmentLightStrength", environmentLightStrength);
        material.SetFloat("_NormalStrength", normalStrength);
        material.SetFloat("_FoamDepthAttenuation", foamDepthAttenuation);
        material.SetFloat("_HeightModifier", heightModifier);
        material.SetFloat("_BubbleDensity", bubbleDensity);

        //material.SetFloat("_DisplacementDepthAttenuation", displacementDepthFalloff);
        
        
        material.SetFloat("_WavePeakScatterStrength", wavePeakScatterStrength);
        material.SetFloat("_ScatterStrength", scatterStrength);
        material.SetFloat("_ScatterShadowStrength", scatterShadowStrength);
        



        SetFFTUniforms();
        if (updateSpectrum)
        {
            SetSpectrumBuffers();
            waterFFTShader.SetTexture(0, "InitSpectrumTexture", _initSpectrum);
            //waterFFTShader.SetTexture(0, "target", target);
            waterFFTShader.Dispatch(0, threadGroupsX, threadGroupsY, 1);
            waterFFTShader.SetTexture(1, "InitSpectrumTexture", _initSpectrum);
            //waterFFTShader.SetTexture(1, "target", target);
            waterFFTShader.Dispatch(1, threadGroupsX, threadGroupsY, 1);
        }

        //Progress Spectrum For FFT
        waterFFTShader.SetTexture(2, "InitSpectrumTexture", _initSpectrum);
        waterFFTShader.SetTexture(2, "SpectrumTexture", _spectrum);
        //waterFFTShader.SetTexture(2, "target", target);
        waterFFTShader.Dispatch(2, threadGroupsX, threadGroupsY, 1);

        // Compute FFT For Height
        InverseFFT(_spectrum);

        // Assemble maps
        waterFFTShader.SetTexture(5, "DisplacementTexture", _displacement);
        waterFFTShader.SetTexture(5, "SpectrumTexture", _spectrum);
        waterFFTShader.SetTexture(5, "SlopeTexture", _slope);
        //waterFFTShader.SetTexture(5, "target", target);
        waterFFTShader.Dispatch(5, threadGroupsX, threadGroupsY, 1);

        _displacement.GenerateMips();
        _slope.GenerateMips();

        material.SetTexture("DisplacementTexture", _displacement);
        material.SetTexture("SlopeTexture", _slope);
    }
}

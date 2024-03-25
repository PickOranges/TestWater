using System;
using UnityEngine;
using UnityEngine.Rendering;
using static UnityEditor.Searcher.SearcherWindow.Alignment;


public class TestScript : MonoBehaviour
{
    public ComputeShader waterFFTShader;
    public Shader waterRenderingShader;
    Camera _camera;
    RenderTexture _target;
    Mesh mesh;
    Material material;
    Vector3[] verts;
    int[] tris;
    Vector3[] normals;
    float g = 9.81f;
    ComputeBuffer spectrumParamsBuffer;

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
        public float windSpeed; // new
    }
    SpectrumSettings[] spectrums = new SpectrumSettings[8];

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
    public DisplaySpectrumSettings spectrum0;
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


    private void Start()
    {
        InitRenderTexture();

        waterFFTShader.SetTexture(0, "InitSpectrumTexture", _target);
        _camera = Camera.main;
        spectrumParamsBuffer = new ComputeBuffer(8, 9*sizeof(float));
        SetSpectrumBuffers();

        //CreatePlane();
        //CreateMaterial();
    }
    void InitRenderTexture()
    {
        if (!_target || _target.width != Screen.width || _target.height != Screen.height)
        {
            if (_target) _target.Release();
            _target = new RenderTexture(Screen.width, Screen.height, 0,
                RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
            _target.enableRandomWrite = true;
            _target.Create();
        }
    }
    private void Update()
    {
        int groupX = _target.width / 8;
        int groupY=_target.height / 8;
        waterFFTShader.Dispatch(0,groupX,groupY,1);

        RenderPipelineManager.endCameraRendering += OnEndCameraRendering;
    }
   
    void OnEndCameraRendering(ScriptableRenderContext context, Camera camera)
    {
        if (!_target)
        {
            //Debug.Log("RenderTexture is empty.");
            return;
        }
        Graphics.Blit(_target, camera.targetTexture);
    }

    // Q: which one/what kind of data types should be released explicitly ???
    private void OnDestroy()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;
        spectrumParamsBuffer.Release();
    }

    void CreatePlane()
    {
        GetComponent<MeshFilter>().mesh = mesh = new Mesh();
        int length = 100;
        float halfL = length * 0.5f;
        int res = 2;
        int sideCnt = length * res;
        int num_vert = sideCnt * sideCnt;
        verts = new Vector3[(sideCnt+1)* (sideCnt + 1)];  // +1 to avoid triangle idx access the vertex index that goes out of bound.
        tris = new int[num_vert*6];

        Vector2[] uv = new Vector2[verts.Length];
        Vector4[] tangents = new Vector4[verts.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);
        mesh.name = "WaterPlane";
        //mesh.indexFormat = IndexFormat.UInt32;
        
        // fill verts
        float deltaLength=(float)length/sideCnt;
        for(int i=0, x=0; x<=sideCnt; ++x)
        {
            for (int z=0; z<=sideCnt; ++z, ++i){
                verts[i] = new Vector3( x*deltaLength-halfL, 0, z*deltaLength - halfL);  // init vert coordinates, later vert.y will be replaced with the real height.
                uv[i] = new Vector2((float)x / sideCnt, (float)z / sideCnt);
                tangents[i] = tangent;
            }
        }
        
        // fill tris
        for (int vi=0, ti=0, x=0; x<sideCnt; ++x)
        {
            for(int z=0; z<sideCnt; ++z, ++vi)
            {
                tris[ti++] = vi;
                tris[ti++] = vi + 1;
                tris[ti++] = vi + 2 + sideCnt;

                tris[ti++] = vi;
                tris[ti++] = vi + sideCnt + 2;
                tris[ti++] = vi + sideCnt + 1;
            }
        }

        mesh.vertices = verts;
        mesh.triangles = tris;
        mesh.RecalculateNormals();
        normals=mesh.normals;
        mesh.uv = uv;
        mesh.tangents = tangents;
       
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
        computeSettings.windSpeed = displaySettings.windSpeed;
    }

    void SetSpectrumBuffers()
    {
        FillSpectrumStruct(spectrum0, ref spectrums[0]);
        FillSpectrumStruct(spectrum1, ref spectrums[1]);
        FillSpectrumStruct(spectrum2, ref spectrums[2]);
        FillSpectrumStruct(spectrum3, ref spectrums[3]);
        FillSpectrumStruct(spectrum4, ref spectrums[4]);
        FillSpectrumStruct(spectrum5, ref spectrums[5]);
        FillSpectrumStruct(spectrum6, ref spectrums[6]);
        FillSpectrumStruct(spectrum7, ref spectrums[7]);

        spectrumParamsBuffer.SetData(spectrums);
        waterFFTShader.SetBuffer(0, "Sps", spectrumParamsBuffer);
    }
}

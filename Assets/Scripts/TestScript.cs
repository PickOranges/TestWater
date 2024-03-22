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

    private void Start()
    {
        InitRenderTexture();
        waterFFTShader.SetTexture(0, "Result", _target);
        _camera = Camera.main;

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

    private void OnDestroy()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;
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
}

using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class Polytope : MonoBehaviour
{

    [SerializeField, Range(2, 5)] int Degrees = 3;
    [SerializeField] Vector3 Rotation;

    [SerializeField, Range(0.001f, 0.2f)] float VertexRadius = .03f;
    [SerializeField, Range(0.001f, 0.2f)] float SegmentRadius = .01f;

    [SerializeField, Range(0.0f, 1.0f)] float U = 1.0f;
    [SerializeField, Range(0.0f, 1.0f)] float V = 0.0f;
    [SerializeField, Range(0.0f, 1.0f)] float W = 0.0f;
    [SerializeField, Range(0.0f, 1.0f)] float T = 0.0f;

    [SerializeField] float TimeScale = .1f;

    [SerializeField] float WorldScale = .1f;

    MaterialPropertyBlock prop = null;

    MeshRenderer Renderer;

    void Start()
    {
        Renderer = GetComponent<MeshRenderer>();
    }

    // Update is called once per frame
    void Update()
    {
        if (prop == null) prop = new MaterialPropertyBlock();

        prop.SetInt("_Degrees", Degrees);
        prop.SetVector("_Rotation", Rotation);
        prop.SetFloat("_VRad", VertexRadius);
        prop.SetFloat("_SRad", SegmentRadius);
        prop.SetFloat("_U", U);
        prop.SetFloat("_V", V);
        prop.SetFloat("_W", W);
        prop.SetFloat("_T", T);

        prop.SetFloat("_time", Time.time*20);
        prop.SetFloat("_TimeScale", TimeScale);

        prop.SetFloat("_Scale", WorldScale);


        Renderer.SetPropertyBlock(prop);
    }
}

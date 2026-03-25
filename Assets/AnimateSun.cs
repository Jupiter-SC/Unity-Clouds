using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Splines;

public class AnimateSun : MonoBehaviour
{
    [SerializeField] SplineAnimate splineAnimate;
    [SerializeField] Vector3 startRot, endRot;

    void Update()
    {
        transform.rotation = Quaternion.Lerp(Quaternion.Euler(startRot), Quaternion.Euler(endRot), splineAnimate.NormalizedTime);
    }
}

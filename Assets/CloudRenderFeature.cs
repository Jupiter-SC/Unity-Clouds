using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class CloudRenderFeature : ScriptableRendererFeature
{
    /// <summary>
    /// Editing shader settings
    /// </summary>
    [System.Serializable]
    public class CloudSettings
    {
        public Material material;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        public Color color = new Color(.5f, .5f, .5f, 1);
        
        public Vector3 boundsMin = new Vector3(-5, -5, -5), boundsMax = new Vector3(5, 5, 5);
        public float stepSize = .1f;
        
        public Texture3D tex3D;

        [Header("Noise Settings")] 
        
        [Range(0,1)] public float cloudScale = 1;
        public Vector3 cloudOffset = Vector3.zero;
        [Range(0, 10)] public float offsetScrollingSpeed = 1;
        
        [Range(0,1)] public float densityThreshold = 0;
        [Min(0)] public float densityMultiplier = 1;

        [Range(0,16)] public int lightSteps = 16;

        [Range(0,1)] public float lightAbsToSun;
        
        [Range(0,1)] public float darkThresh;

        [Header("Phase Settings")]
        
        [Range(0, 1), Tooltip("How much influence the follow actually have on lighting")] public float phaseFactor;
        
        [Range(0,.9f)] public float forwardScatteringK;
        
        [Range(0,.9f)] public float backwardScatteringK;
        
        [Range(0,1)] public float baseBrightness;

    }

    /// <summary>
    /// Setup pass and set Uniforms
    /// </summary>
    class CloudPass : ScriptableRenderPass
    {
        public CloudSettings settings;
        private RenderTargetIdentifier source;
        RenderTargetHandle tempTexture;
        private string profilerTag;

        public void Setup(RenderTargetIdentifier source)
        {
            this.source = source;
        }

        public CloudPass(string profilerTag)
        {
            this.profilerTag = profilerTag;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            cmd.GetTemporaryRT(tempTexture.id, cameraTextureDescriptor);
            ConfigureTarget(tempTexture.Identifier());
            ConfigureClear(ClearFlag.All, Color.black);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(profilerTag);
            cmd.Clear();

            if (settings.material == null) return;

            settings.material.SetColor("_Color", settings.color);
            settings.material.SetVector("_BoundsMin", settings.boundsMin);
            settings.material.SetVector("_BoundsMax", settings.boundsMax);
            settings.material.SetTexture("_3DTex", settings.tex3D);
            settings.material.SetFloat("_StepSize", settings.stepSize);
            
            settings.material.SetFloat("_CloudScale", settings.cloudScale / 100f);
            settings.material.SetVector("_CloudOffset", settings.cloudOffset);
            settings.material.SetFloat("_OffsetSpeed", settings.offsetScrollingSpeed);
            
            settings.material.SetFloat("_DensityThreshold", settings.densityThreshold);
            settings.material.SetFloat("_DensityMultiplier", settings.densityMultiplier);
            
            settings.material.SetInt("_LightSteps", settings.lightSteps);
            settings.material.SetFloat("_LightAbsorbtionTowardsSun", settings.lightAbsToSun);
            settings.material.SetFloat("_DarknessThreshold", settings.darkThresh);
            
            settings.material.SetFloat("_ForwardScatteringK", settings.forwardScatteringK);
            settings.material.SetFloat("_BackwardsScatteringK", settings.backwardScatteringK);
            settings.material.SetFloat("_BaseBrightness", settings.baseBrightness);
            settings.material.SetFloat("_PhaseFactor", settings.phaseFactor);
            
            cmd.Blit(source, tempTexture.Identifier());
            cmd.Blit(tempTexture.Identifier(), source, settings.material, 0);

            context.ExecuteCommandBuffer(cmd);
            
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
    
    public CloudSettings settings = new CloudSettings();

    private CloudPass pass;

    public override void Create()
    {
        pass = new CloudPass("Cloud Pass");
        name = "Cloud Pass";
        pass.settings = settings;
        pass.renderPassEvent = settings.renderPassEvent;
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        var cameraColorTargetIdent = renderer.cameraColorTarget;
        pass.Setup(cameraColorTargetIdent);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

}

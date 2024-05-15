#version 330 core
#ifdef GL_ES
precision mediump float;
#endif
uniform sampler2D texture_diffuse1;
uniform bool useDiffuse;
uniform sampler2D texture_specular1;
uniform bool useSpecular;
uniform sampler2D texture_normal1;
uniform bool useNormal;
uniform sampler2D texture_height1;
uniform bool useHeight;
uniform sampler2D texture_metallic1;
uniform bool useMetallic;
uniform sampler2D texture_roughness1;
uniform bool useRoughness;
uniform sampler2D texture_emission1;
uniform bool useEmission;
uniform sampler2D uShadowMap;

uniform bool useTexture;
uniform vec3 uLightdirection;
uniform vec3 uCameraPos;
uniform float uLightIntensity;

uniform mat4 uLightSpaceMatrix;

uniform vec3 uLightColor;

uniform samplerCube irradianceMap;

uniform samplerCube prefilterMap;

uniform sampler2D brdfLUTTexture;



in highp vec2 vTextureCoord;
in highp vec3 vFragPos_WS;
in highp vec3 vNormal_WS;
in highp vec3 vTangent_WS;

out vec4 FragColor;


const float PI = 3.14159265359;
#define POISSON_COUNT 16
#define POISSON_DISK vec2[POISSON_COUNT] \
    (vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.094184101, -0.92938870), vec2(0.34495938, 0.29387760), \
    vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464), vec2(-0.38277543, 0.27676845), vec2(0.97484398, 0.75648379), \
    vec2(0.586331, -0.310612), vec2(-0.207107, -0.978156), vec2(-0.567129, 0.271440), vec2(-0.792657, -0.213023), \
    vec2(0.240993, 0.963973), vec2(-0.959492, 0.265046), vec2(0.396143, -0.841747), vec2(-0.136509, 0.975315))

float poissonDiskSample(vec2 uv, float radius,float currentDepth) {
    vec2 poissonDisk[POISSON_COUNT] = POISSON_DISK;
    float depthSum = 0.0;
    for(int i = 0; i < POISSON_COUNT; ++i) {
        float depth = texture2D(uShadowMap, uv + radius * poissonDisk[i]).r;
        depthSum += currentDepth >  depth ? 1.0 : 0.0;
    }
    float averageDepth = depthSum / float(POISSON_COUNT);

    return averageDepth;
}

float CalcShadowFactor(vec3 _vFragPos_WS, vec3 normal, vec3 lightDir) {
  vec4 shadowCoord_H = uLightSpaceMatrix * vec4(_vFragPos_WS, 1.0);
  vec3 shadowCoord = shadowCoord_H.xyz / shadowCoord_H.w;
  shadowCoord = shadowCoord * 0.5 + 0.5;
  vec2 texelSize = 1.0 / textureSize(uShadowMap, 0);
  float bias = max(0.007 * (1.0 - dot(normal, lightDir)), 0.007);
  float currentDepth = shadowCoord.z -bias ;

  //计算平均深度遮挡物采样大小
  int maxSearchSize = 33;
  int minSearchSize = 3;
  float s = int (currentDepth - 1)/(20 - 1) ;
  int blocksize = minSearchSize + int(s * (maxSearchSize - minSearchSize));

  //计算阴影的平均深度
  float AverageDepth =0;
  float Averagenum = 0;
  for(int i = -blocksize; i < blocksize; ++i)
  {
    for(int j = -blocksize; j < blocksize; ++j)
    {
      float Depth = texture(uShadowMap, shadowCoord.xy + vec2(i, j) * texelSize).r; 
      if(shadowCoord.z > Depth)
      {
        AverageDepth += Depth;
        Averagenum += 1.0;
      }
    }
  }
  if (Averagenum == 0) {
    return 0;
  }
  AverageDepth /= Averagenum;


  float lightsize =100;
  float point2BlockerDistance = length((currentDepth - AverageDepth) );

  float depthlod = 0.0;


  depthlod = point2BlockerDistance * lightsize / AverageDepth;
  
  float shadow = 0.0;
  
  shadow  = poissonDiskSample(shadowCoord.xy,  depthlod * texelSize.x, currentDepth);

  
  if(shadowCoord.z > 1.0)
    shadow = 0;
  return shadow;
}

vec3 CalcLightingTerm(vec3 LightColor, vec3 lightDir, vec3 WorldNormal) {
  vec3 wi = normalize(lightDir);
  float cosTheta = max(dot(WorldNormal, wi), 0.0);
  vec3 radiance = LightColor * cosTheta;
  return radiance;
}

vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness,vec3 F90)
{
    return F0 + (max(vec3(1.0 - roughness)*F90, F0) - F0) * pow(1.0 - cosTheta, 5.0);
}   


float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a      = roughness*roughness;
    float a2     = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float num   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeometrySchlickGGX(NdotV, roughness);
    float ggx1  = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}




void main() {

vec3 color;
  if (useTexture) {
      color = pow(texture2D(texture_diffuse1, vTextureCoord).rgb, vec3(2.2));
  } else {
      color = vec3(0.7);
  }

  float metallic = 0.3;
  if(useMetallic)
  {
    metallic = texture2D(texture_metallic1,vTextureCoord).r;
  }

  float roughness = 0.3;
  if(useRoughness)
  {
    roughness = texture2D(texture_roughness1,vTextureCoord).r;
  }
  vec3 lightDir = -normalize(uLightdirection);
  vec3 normal = normalize(vNormal_WS);
  // 法线贴图
  if(useNormal)
  {
    vec3 normalTexture = texture(texture_normal1, vTextureCoord).rgb;
    normalTexture = normalTexture * 2.0 - 1.0; // 将法线贴图的颜色从[0,1]转换到[-1,1]
    vec3 T = normalize(vTangent_WS);
    vec3 N = normalize(vNormal_WS);
    vec3 B = cross(N, T);
    mat3 TBN = mat3(T, B, N); // 切线空间到世界空间的变换矩阵
    normal = normalize(TBN * normalTexture); // 将法线从切线空间转换到世界空间

  }

  //
  float shadow = CalcShadowFactor(vFragPos_WS, normal, lightDir);//计算阴影
  vec3 viewDir = normalize(uCameraPos - vFragPos_WS);
  vec3 halfwayDir = normalize(lightDir + viewDir);

  //环境光
  vec3 ambient =  texture(irradianceMap, normal).rgb;
  

  //光照项
  vec3 R = reflect(-viewDir, normal); 
  const float MAX_REFLECTION_LOD = 3.0;
  
  vec3 prefilteredColor = textureLod(prefilterMap, R,  roughness * MAX_REFLECTION_LOD).rgb;  
  
  vec3 irradiance  = texture(irradianceMap, normal).rgb;

  //计算镜面反射brdf项
  vec3 F0 = vec3(0.04);
  vec3 F        = fresnelSchlickRoughness(max(dot(normal, viewDir), 0.0), F0, roughness,color);
  vec2 envBRDF  = texture(brdfLUTTexture, vec2(max(dot(normal, viewDir), 0.0), roughness)).rg;
  vec3 specular = prefilteredColor * (F * envBRDF.x + envBRDF.y);

  //计算漫反射brdf项
  vec3 kS = F; 
  vec3 kD = vec3(1.0) - kS;
  kD *= 1.0 - metallic;  

  float NdotL = max(dot(normal, lightDir), 0.0);

  vec3 diffuse = kD * color * irradiance;


  //计算反射方程
  vec3 Lo = specular + diffuse;

  Lo = Lo/(1.0 + Lo);

  // 计算阴影
  float shadowFactor = 1.0 - shadow * 0.3;
  shadowFactor = mix(shadowFactor, 1.0, 0.5); // 调整阴影混合因子，使阴影更柔和
  vec3 lighting = Lo * shadowFactor;

  FragColor = vec4(pow(vec3(lighting),vec3(1.0/2.2)),1.0);
}


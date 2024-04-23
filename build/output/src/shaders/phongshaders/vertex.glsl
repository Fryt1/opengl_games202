#version 330 core
in vec3 aVertexPosition;
in vec3 aNormalPosition;
in vec2 aTextureCoord;

uniform mat4 uViewMatrix;
uniform mat4 uModelMatrix;
uniform mat4 uProjectionMatrix;
uniform mat3 uModelToWorldNormalMatrix;

out highp vec2 vTextureCoord;
out highp vec3 vFragPos_WS;
out highp vec3 vNormal_WS;

void main() {

  vFragPos_WS = (uModelMatrix * vec4(aVertexPosition, 1.0)).xyz;

  vNormal_WS = uModelToWorldNormalMatrix * aNormalPosition;

  vTextureCoord = aTextureCoord;

  gl_Position = uProjectionMatrix * uViewMatrix * uModelMatrix*vec4(aVertexPosition, 1.0);

}
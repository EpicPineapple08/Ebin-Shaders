#include "/../shaders/lib/Syntax.glsl"


varying vec2 texcoord;

#include "/../shaders/lib/Uniform/Shading_Variables.glsl"


/***********************************************************************/
#if defined vsh

uniform sampler3D colortex7;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float sunAngle;
uniform float far;

#include "/../shaders/lib/Settings.glsl"
#include "/../shaders/lib/Utility.glsl"
#include "/../shaders/lib/Debug.glsl"
#include "/../shaders/lib/Uniform/Projection_Matrices.vsh"
#include "/../shaders/UserProgram/centerDepthSmooth.glsl"
#include "/../shaders/lib/Uniform/Shadow_View_Matrix.vsh"
#include "/../shaders/lib/Fragment/PrecomputedSky.glsl"
#include "/../shaders/lib/Vertex/Shading_Setup.vsh"

void main() {
	texcoord    = gl_MultiTexCoord0.st;
	gl_Position = ftransform();
	
	gl_Position.xy = ((gl_Position.xy * 0.5 + 0.5) * COMPOSITE0_SCALE) * 2.0 - 1.0;
	
	
	SetupProjection();
	SetupShading();
}

#endif
/***********************************************************************/



/***********************************************************************/
#if defined fsh

const bool shadowtex1Mipmap    = true;
const bool shadowcolor0Mipmap  = true;
const bool shadowcolor1Mipmap  = true;

const bool shadowtex1Nearest   = true;
const bool shadowcolor0Nearest = true;
const bool shadowcolor1Nearest = false;

uniform sampler2D colortex0;
uniform sampler2D colortex4;
uniform sampler2D gdepthtex;
uniform sampler2D depthtex1;
uniform sampler2D noisetex;
uniform sampler2D shadowcolor;
uniform sampler2D shadowcolor1;
uniform sampler2D shadowtex1;
uniform sampler2DShadow shadow;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;

uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;

uniform int isEyeInWater;

#include "/../shaders/lib/Settings.glsl"
#include "/../shaders/lib/Utility.glsl"
#include "/../shaders/lib/Debug.glsl"
#include "/../shaders/lib/Uniform/Projection_Matrices.fsh"
#include "/../shaders/lib/Uniform/Shadow_View_Matrix.fsh"
#include "/../shaders/lib/Fragment/Masks.fsh"

float GetDepth(vec2 coord) {
	return textureRaw(gdepthtex, coord).x;
}

float GetDepthLinear(vec2 coord) {
	return (near * far) / (textureRaw(gdepthtex, coord).x * (near - far) + far);
}

vec3 CalculateViewSpacePosition(vec3 screenPos) {
	screenPos = screenPos * 2.0 - 1.0;
	
	return projMAD(projInverseMatrix, screenPos) / (screenPos.z * projInverseMatrix[2].w + projInverseMatrix[3].w);
}

vec3 GetNormal(vec2 coord) {
	return DecodeNormal(textureRaw(colortex4, coord).xy);
}


vec2 GetDitherred2DNoise(vec2 coord, float n) { // Returns a random noise pattern ranging {-1.0 to 1.0} that repeats every n pixels
	coord *= vec2(viewWidth, viewHeight);
	coord  = mod(coord, vec2(n));
	return texelFetch(noisetex, ivec2(coord), 0).xy;
}

#include "/../shaders/lib/Fragment/ComputeGI.fsh"
#include "/../shaders/lib/Fragment/ComputeSSAO.fsh"
#include "/../shaders/lib/Fragment/ComputeVolumetricLight.fsh"

/* DRAWBUFFERS:56 */
#include "/../shaders/lib/Exit.glsl"

void main() {
	float depth0 = GetDepth(texcoord);
	
#ifndef VOLUMETRIC_LIGHT
	if (depth0 >= 1.0) { discard; }
#endif
	
	
#ifdef COMPOSITE0_NOISE
	vec2 noise2D = GetDitherred2DNoise(texcoord * COMPOSITE0_SCALE, 4.0) * 2.0 - 1.0;
#else
	vec2 noise2D = vec2(0.0);
#endif
	
	vec2 texure4 = textureRaw(colortex4, texcoord).rg;
	
	vec4  decode4       = Decode4x8F(texure4.r);
	Mask  mask          = CalculateMasks(decode4.r);
	float smoothness    = decode4.g;
	float torchLightmap = decode4.b;
	float skyLightmap   = decode4.a;
	
	float depth1 = (mask.hand > 0.5 ? depth0 : textureRaw(depthtex1, texcoord).x);
	
	mat2x3 backPos;
	backPos[0] = CalculateViewSpacePosition(vec3(texcoord, depth1));
	backPos[1] = mat3(gbufferModelViewInverse) * backPos[0];
	
	mat2x3 frontPos;
	frontPos[0] = CalculateViewSpacePosition(vec3(texcoord, depth0));
	frontPos[1] = mat3(gbufferModelViewInverse) * frontPos[0];
	
	if (depth0 != depth1)
		mask.water = Decode4x8F(texture2D(colortex0, texcoord).r).b;
	
	vec2 VL = ComputeVolumetricLight(backPos[1], frontPos[1], noise2D, mask.water);
	
	gl_FragData[1] = vec4(VL, 0.0, 0.0);
	
	if (depth1 >= 1.0) // Back surface is sky
		{ gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0); exit(); return; }
	
	
	vec3 normal = DecodeNormal(texure4.g, 11);
	
	float AO = ComputeSSAO(backPos[0], normal * mat3(gbufferModelViewInverse));
	
	if (isEyeInWater != mask.water) // If surface is in water
		{ gl_FragData[0] = vec4(0.0, 0.0, 0.0, AO); exit(); return; }
	
	
	vec3 GI = ComputeGI(backPos[1], normal, skyLightmap, GI_RADIUS * 2.0, noise2D, mask);
	
	gl_FragData[0] = vec4(sqrt(GI * 0.2), AO);
	
	exit();
}

#endif
/***********************************************************************/

#version 120

/* DRAWBUFFERS:2 */

#include "include/PostHeader.fsh"
#include "include/GlobalCompositeVariables.fsh"

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D gdepthtex;
uniform sampler2D shadowcolor;
uniform sampler2DShadow shadow;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;
uniform mat4 shadowModelViewInverse;

varying vec2 texcoord;


#include "/include/ShadingStructs.fsh"


float GetMaterialIDs(in vec2 coord) {    //Function that retrieves the texture that has all material IDs stored in it
	return texture2D(colortex3, coord).b;
}

vec3 GetDiffuse(in vec2 coord) {
	return texture2D(colortex2, coord).rgb;
}

float GetTorchLightmap(in vec2 coord) {
	return texture2D(colortex3, coord).r;
}

float GetSkyLightmap(in vec2 coord) {
	return texture2D(colortex3, coord).g;
}

vec3 DecodeNormal(vec2 encodedNormal) {
	encodedNormal = encodedNormal * 2.0 - 1.0;
    vec2 fenc = encodedNormal * 4.0 - 2.0;
	float f = dot(fenc, fenc);
	float g = sqrt(1.0 - f / 4.0);
	return vec3(fenc * g, 1.0 - f / 2.0);
}

vec3 GetNormal(in vec2 coord) {
	return DecodeNormal(texture2D(colortex0, coord).xy);
}

float GetDepth(in vec2 coord) {
	return texture2D(gdepthtex, coord).x;
}

vec4 GetViewSpacePosition(in vec2 coord, in float depth) {
	vec4 position  = gbufferProjectionInverse * vec4(vec3(coord, depth) * 2.0 - 1.0, 1.0);
	     position /= position.w;
	
	return position;
}


#include "include/ShadingFunctions.fsh"


void main() {
	#ifndef DEFERRED_SHADING    //Program unloading only seems to work with composite, not composite1, unfortunately
		gl_FragData[0] = vec4(texture2D(colortex2, texcoord));
		return;
	#endif
	
	Mask mask;
	CalculateMasks(mask, GetMaterialIDs(texcoord), true);
	
	if (mask.sky > 0.5) { gl_FragData[0] = vec4(texture2D(colortex2, texcoord).rgb, 1.0); return; }
	
	
	vec3  diffuse           = GetDiffuse(texcoord);
	float torchLightmap     = GetTorchLightmap(texcoord);
	float skyLightmap       = GetSkyLightmap(texcoord);
	vec3  normal            = GetNormal(texcoord);
	float depth             = GetDepth(texcoord);
	vec4  viewSpacePosition = GetViewSpacePosition(texcoord, depth);
	
	
	vec3 composite = CalculateShadedFragment(diffuse, mask, torchLightmap, skyLightmap, normal, viewSpacePosition);
	
	gl_FragData[0] = vec4(composite, 1.0);
}
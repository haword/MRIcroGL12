//pref
brighten|float|0.5|2|3.5
surfaceColor|float|0.0|1.0|1.0
overlayFuzzy|float|0.01|0.5|1
overlayDepth|float|0.0|0.15|0.99
//vert
#version 330 core
layout(location = 0) in vec3 vPos;
out vec3 TexCoord1;
out vec4 vPosition;
uniform mat4 ModelViewProjectionMatrix;
void main() {
  TexCoord1 = vPos;
  gl_Position = ModelViewProjectionMatrix * vec4(vPos, 1.0);
  vPosition = gl_Position;
}
//frag
#version 330 core
in vec3 TexCoord1;
out vec4 FragColor;
in vec4 vPosition;
uniform int loops;
uniform float stepSize, sliceSize;
uniform sampler3D intensityVol, gradientVol;
uniform sampler3D intensityOverlay, gradientOverlay;
uniform vec3 lightPosition, rayDir;
uniform vec4 clipPlane;
uniform float brighten = 1.5;
uniform float surfaceColor = 1.0;
uniform float overlayDepth = 0.3;
uniform float overlayFuzzy = 0.5;
uniform int overlays = 0;
uniform float backAlpha = 0.5;
uniform mat3 NormalMatrix;

uniform sampler2D matcap2D;
vec3 GetBackPosition (vec3 startPosition) { //when does ray exit unit cube http://prideout.net/blog/?p=64
	vec3 invR = 1.0 / rayDir;
    vec3 tbot = invR * (vec3(0.0)-startPosition);
    vec3 ttop = invR * (vec3(1.0)-startPosition);
    vec3 tmax = max(ttop, tbot);
    vec2 t = min(tmax.xx, tmax.yz);
	return startPosition + (rayDir * min(t.x, t.y));
}
void main() {
    vec3 start = TexCoord1.xyz;
	vec3 backPosition = GetBackPosition(start);
	vec3 dir = backPosition - start;
	float len = length(dir);
	//if (len <= stepSize)  {
	//	FragColor = vec4(1.0,0.0,0.0,1.0);
	//	return;
	//}
	dir = normalize(dir);
	vec3 deltaDir = dir * stepSize;
	vec4 gradSample, colorSample;
	float bgNearest = len; //assume no hit
	float overFarthest = len;
	float diffuse = 0.3;
	float specular = 0.25;
	float shininess = 10.0;
	vec4 overAcc = vec4(0.0,0.0,0.0,0.0);
	vec4 colAcc = vec4(0.0,0.0,0.0,0.0);
	vec4 prevGrad = vec4(0.0,0.0,0.0,0.0);
	float lengthAcc = 0.0;
	vec3 samplePos;
	//overlay pass
	if ( overlays > 0 ) {
		samplePos = start.xyz +deltaDir* (fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453));
		while (lengthAcc <= len) {
			colorSample = texture(intensityOverlay,samplePos);
			if (colorSample.a > 0.00) {
				colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
				colorSample.a *=  overlayFuzzy;
				float s =  0;
				vec3 d = vec3(0.0, 0.0, 0.0);
				overFarthest = lengthAcc;
				//gradient based lighting http://www.mccauslandcenter.sc.edu/mricrogl/gradients
				gradSample = texture(gradientOverlay,samplePos); //interpolate gradient direction and magnitude
				gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
				//reusing Normals http://www.marcusbannerman.co.uk/articles/VolumeRendering.html
				if (gradSample.a < prevGrad.a)
					gradSample.rgb = prevGrad.rgb;
				prevGrad = gradSample;
				float lightNormDot = dot(gradSample.rgb, lightPosition);
				d = max(lightNormDot, 0.0) * colorSample.rgb * diffuse;
				s =   specular * pow(max(dot(reflect(lightPosition, gradSample.rgb), dir), 0.0), shininess);

				colorSample.rgb = colorSample.rgb + d + s;
				colorSample.rgb *= colorSample.a;
				colAcc= (1.0 - colAcc.a) * colorSample + colAcc;
				if ( colAcc.a > 0.95 )
					break;
			}
			samplePos += deltaDir;
			lengthAcc += stepSize;
		} //while lengthAcc < len
		colAcc.a = colAcc.a/0.95;
		overAcc = colAcc; //color accumulated by overlays
		//clear values for background
		colAcc = vec4(0.0,0.0,0.0,0.0);
		prevGrad = vec4(0.0,0.0,0.0,0.0);
		lengthAcc = 0.0;
	} //if overlayNum > 0
	bgNearest = len; //assume no hit
	//end ovelay pass clip plane applied to background ONLY...
	samplePos = start.xyz +deltaDir* (fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453));
	if (clipPlane.a > -0.5) {
		bool frontface = (dot(dir , clipPlane.xyz) > 0.0);
		float dis = dot(dir,clipPlane.xyz);
		if (dis != 0.0  )  dis = (-clipPlane.a - dot(clipPlane.xyz, start.xyz-0.5)) / dis;
		//test: "return" fails on 2006MacBookPro10.4ATI1900, "discard" fails on MacPro10.5NV8800
		if (((frontface) && (dis >= len)) || ((!frontface) && (dis <= 0.0)))
			lengthAcc = len + 1.0; //no background
		else if ((dis > 0.0) && (dis < len)) {
			if (frontface) {
				lengthAcc = dis;
				//stepSizeX2 = dis;
				samplePos += dir * dis;
				//len -= dir * dis;
			} else {
				backPosition =  start + dir * (dis);
				len = length(backPosition - start);
			}
		}
	}
	float stepSizeX2 = lengthAcc + (stepSize * 2.0);
	vec3 defaultDiffuse = vec3(0.9, 0.9, 0.9);
	float alphaThresh = 0.95;
	vec4 gradAcc = vec4(0.0, 0.0, 0.0, 0.0);
	colAcc = gradAcc;
	vec4 gradMax = gradAcc;
	vec4 colorMax = gradMax;
	while (lengthAcc <= len) {
		colorSample = texture(intensityVol,samplePos);
		if (colorSample.a > 0.001) {
			colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
			colorMax = mix(colorMax, colorSample, max(sign(colorSample.a - colorMax.a), 0.0));
			//if (colorSample.a > colorMax.a)
			//	colorMax = colorSample;
			bgNearest = min(lengthAcc,bgNearest);
			if (lengthAcc > stepSizeX2) {
				gradSample= texture(gradientVol,samplePos);
				gradMax = mix(gradMax, gradSample, max(sign(gradSample.a - gradMax.a), 0.0));
				//if (gradSample.a > gradMax.a)
				//	gradMax = gradSample;
					
			} else
				colorSample.a = clamp(colorSample.a*3.0,0.0, 1.0);
			colAcc= (1.0 - colAcc.a) * colorSample + colAcc;
			if (colAcc.a > alphaThresh)
				break;
		
		}
		samplePos += deltaDir;
		lengthAcc += stepSize;
	} //while lengthAcc < len
	if  (gradMax.a > 0.00) {
		gradSample = gradMax;
		gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
		vec3 n = normalize(normalize(NormalMatrix * gradSample.rgb));
		vec2 uv = n.xy * 0.5 + 0.5;
		vec3 d = texture(matcap2D,uv.xy).rgb;
		vec3 surf = mix(defaultDiffuse, colorMax.rgb, surfaceColor); //0.67 as default Brighten is 1.5
		colorSample.rgb = d * surf * (brighten / 2.0);
		colAcc.rgb = colorSample.rgb;
	}
	
	
	colAcc.a = colAcc.a/0.95;
	colAcc.a *= backAlpha;
	//if (overAcc.a > 0.0) { //<- conditional not required: overMix always 0 for overAcc.a = 0.0
		float overMix = overAcc.a;
		if (((overFarthest) > bgNearest) && (colAcc.a > 0.0)) { //background (partially) occludes overlay
			//max distance between two vertices of unit cube is 1.73
			//float dx = (overNearest - bgNearest)/1.73;
			float dx = (overFarthest - bgNearest)/1.73;
			//float dx = (overNearest - bgMeanDepth)/1.73;
			//float dx = (overMeanDepth - bgNearest)/1.73;


			//dx = min(dx, 0.00001);
			dx = colAcc.a * pow(dx, overlayDepth);
			//dx = colAcc.a;
			overMix *= 1.0 - dx;
		}
		colAcc.rgb = mix(colAcc.rgb, overAcc.rgb, overMix);
		colAcc.a = max(colAcc.a, overAcc.a);
	//}
    FragColor = colAcc;
}
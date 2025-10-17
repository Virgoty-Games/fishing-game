	shader_type spatial;
	render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

	/* Buffers de pantalla */
	uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture,  filter_linear_mipmap;
	uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

	/* Agua base */
	uniform float SEA_LEVEL = 0.0;
	uniform float TIME_SCALE = 0.35;

	uniform float AMPL_1 = 0.18;
	uniform float WAVEL_1 = 16.0;
	uniform float STEEP_1 = 0.35;
	uniform vec2  DIR_1 = vec2(1.0, 0.2);

	uniform float AMPL_2 = 0.10;
	uniform float WAVEL_2 = 8.0;
	uniform float STEEP_2 = 0.45;
	uniform vec2  DIR_2 = vec2(-0.6, 1.0);

	uniform float TILING = 0.06;

	uniform vec4  WATER_COLOR : source_color = vec4(0.065,0.18,0.26,1.0);
	uniform vec4  FOAM_COLOR  : source_color = vec4(0.92,0.95,0.98,1.0);
	uniform float U_METALLIC = 0.0;
	uniform float U_ROUGHNESS = 0.2;

	/* Borde de contacto */
	uniform float EDGE_FADE = 0.006;
	uniform float EDGE_STRENGTH = 1.1;

	/* Refracción y “lo de abajo” */
	uniform float REFRACTION = 0.008;
	uniform float UNDER_TINT = 0.18;

	/* Toon suave */
	uniform float QUANTIZATION = 3.0;

	/* Manchas “sub-superficie” (caustics stylized) */
	uniform float CAUSTICS_SCALE   = 0.12;   // tamaño de las manchas (menor = más grandes)
	uniform float CAUSTICS_SPEED   = 0.15;   // velocidad de evolución
	uniform float CAUSTICS_STRENGTH= 0.45;   // cuánto oscurecen
	uniform float CAUSTICS_CONTRAST= 1.35;   // dureza del patrón
	uniform float CAUSTICS_FADE    = 0.35;   // se apagan con el ángulo (fresnel)

	varying float v_ndc_depth;
	varying vec3 v_world_pos;
	varying vec3 v_world_normal;

	/* -------- utilidades de ruido -------- */
	float hash(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
	float noise(vec2 p){ vec2 i=floor(p),f=fract(p);
		float a=hash(i), b=hash(i+vec2(1,0)), c=hash(i+vec2(0,1)), d=hash(i+vec2(1,1));
		vec2 u=f*f*(3.0-2.0*f);
		return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
	}
	float fbm(vec2 p){
		float s=0.0,a=0.5;
		for(int i=0;i<4;i++){ s += a*noise(p); p*=2.02; a*=0.5; }
		return s;
	}
	mat2 rot2(float a){
	    float c = cos(a);
	    float s = sin(a);
	    // columnas: [ c  -s ;  s   c ]
	    return mat2(vec2(c, s), vec2(-s, c));
	}


	/* -------- olas -------- */
	float gerstner(inout vec3 pos, vec2 dir, float A, float L, float steep, float t){
		float k=2.0*PI/L, w=sqrt(9.8*k);
		float ph = dot(dir, pos.xz)*k - w*t;
		float Qa = steep*A;
		pos.x += dir.x*Qa*cos(ph);
		pos.z += dir.y*Qa*cos(ph);
		pos.y += A*sin(ph);
		return sin(ph);
	}

	void vertex(){
		VERTEX.y = SEA_LEVEL;

		vec3 wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
		float t = TIME * TIME_SCALE;

		vec2 d1 = normalize(DIR_1);
		vec2 d2 = normalize(DIR_2);

		vec3 p = wp;
		gerstner(p,d1,AMPL_1,WAVEL_1,STEEP_1,t);
		gerstner(p,d2,AMPL_2,WAVEL_2,STEEP_2,t);

		/* normales */
		float eps=0.25;
		vec3 px = wp + vec3(eps,0.0,0.0);
		vec3 pz = wp + vec3(0.0,0.0,eps);
		gerstner(px,d1,AMPL_1,WAVEL_1,STEEP_1,t);
		gerstner(px,d2,AMPL_2,WAVEL_2,STEEP_2,t);
		gerstner(pz,d1,AMPL_1,WAVEL_1,STEEP_1,t);
		gerstner(pz,d2,AMPL_2,WAVEL_2,STEEP_2,t);

		vec3 dx = px - wp;
		vec3 dz = pz - wp;
		NORMAL = normalize(cross(dz,dx));

		/* devolver a local */
		mat3 inv_model = inverse(mat3(MODEL_MATRIX));
		VERTEX = inv_model * (p - MODEL_MATRIX[3].xyz);

		/* UV de mundo */
		UV = wp.xz * TILING;

		v_world_pos = p;
		v_world_normal = normalize(NORMAL);

		vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p,1.0);
		v_ndc_depth = clip.z / clip.w;
	}

	void fragment(){
		METALLIC  = U_METALLIC;
		ROUGHNESS = U_ROUGHNESS;

		vec3 n = normalize(v_world_normal);
		vec3 cam_pos = (inverse(VIEW_MATRIX))[3].xyz;

		/* borde por profundidad */
		float frag_depth  = v_ndc_depth*0.5 + 0.5;
		float scene_depth = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
		float edge = 1.0 - smoothstep(0.0, EDGE_FADE, abs(scene_depth - frag_depth));
		edge = pow(edge, 0.75)*EDGE_STRENGTH;

		/* refracción y “lo de abajo” */
		vec2 refr_uv = SCREEN_UV + n.xz * REFRACTION;
		vec3 under_col = textureLod(SCREEN_TEXTURE, refr_uv, 0.0).rgb;
		under_col = mix(under_col, WATER_COLOR.rgb, UNDER_TINT);

		/* ——— manchas estilizadas bajo el agua ———
		   dos capas de FBM en world-space, rotadas y a distinta escala,
		   animadas lentamente: dan sombras que cambian orgánicas. */
		vec2 cw = v_world_pos.xz * CAUSTICS_SCALE;
		vec2 a1 = rot2(0.35) * (cw + TIME*CAUSTICS_SPEED);
		vec2 a2 = rot2(-0.8) * (cw*1.7 + TIME*CAUSTICS_SPEED*1.35);
		float m = 0.6*fbm(a1) + 0.4*fbm(a2);
		m = pow(smoothstep(0.35, 0.75, m), CAUSTICS_CONTRAST);   // contraste controlable

		/* fresnel para que se vean más con ángulo rasante, menos en vista frontal */
		float view_fres = pow(1.0 - max(dot(n, normalize(cam_pos - v_world_pos)), 0.0), 2.0);
		float caustics_mask = mix(1.0, view_fres, CAUSTICS_FADE);

		/* oscurecer “debajo” con el patrón, sin teñir demasiado */
		under_col = mix(under_col, under_col*0.6, m * CAUSTICS_STRENGTH * caustics_mask);

		/* toon suave */
		vec3 base = mix(under_col, WATER_COLOR.rgb, 0.7);
		float shade = clamp(n.y*0.9 + 0.1, 0.0, 1.0);
		shade = floor(shade*QUANTIZATION)/QUANTIZATION;
		vec3 col = mix(base*0.86, base*1.12, shade);

		/* fresnel ligero y borde de contacto */
		float fres = pow(1.0 - max(dot(n, normalize(cam_pos - v_world_pos)), 0.0), 5.0);
		col = mix(col, vec3(1.0), fres*0.08);
		col = mix(col, FOAM_COLOR.rgb, edge);

		ALBEDO = col;
		ALPHA = 0.999; /* opaco pero permite la ruta de mezcla adecuada */
	}

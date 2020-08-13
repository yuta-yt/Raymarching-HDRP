#define GBUFFER_MARCHING_ITERATION       64
#define SHADOWCASTER_MARCHING_ITERATION  32
#define MOTIONVECTORS_MARCHING_ITERATION 16
#define MARCHING_ADAPTIVE_EPS_BASE 0.0001

int _Degrees;
float3 _Rotation;

float _VRad;
float _SRad;

float _U;
float _V;
float _W;
float _T;

float _time;
float _TimeScale;

float _Scale;

float3x3 rot3D(float3 axis, float angle)
{
    float c, s;
    sincos(angle, s, c);

    float t = 1 - c;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;

    return float3x3(
        t * x * x + c,      t * x * y - s * z,  t * x * z + s * y,
        t * x * y + s * z,  t * y * y + c,      t * y * z - s * x,
        t * x * z - s * y,  t * y * z + s * x,  t * z * z + c
    );
}

float4 fold(float4 pos, float4 nc, float4 nd) {
	for(int i = 0; i < 25; i++){
		float4 tmp = pos;
		pos.xy=abs(pos.xy);
		
		float t = -2. * min(0., dot(pos,nc));
		pos += t * nc;
		
		t = -2. * min(0., dot(pos, nd));
		pos += t * nd;
		
		if (tmp.x == pos.x &&
			tmp.y == pos.y &&
			tmp.z == pos.z &&
			tmp.w == pos.w) { return pos; }
	}
	return pos;
}

float DD(float ca, float sa, float r){
	//magic formula to convert from spherical distance to planar distance.
	//involves transforming from 3-plane to 3-sphere, getting the distance
	//on the sphere then going back to the 3-plane.
	return r-(2.*r*ca-(1.-r*r)*sa)/((1.-r*r)*ca+2.*r*sa+1.+r*r);
}

float dist2Vertex(float4 p, float4 z, float r, float vRadius){
	float ca=dot(z,p), sa=0.5*length(p-z)*length(p+z);//sqrt(1.-ca*ca);//
	return DD(ca,sa,r)-vRadius;
}

float dist2Segment(float4 p, float4 z, float4 n, float r, float sRadius){
	//pmin is the orthogonal projection of z onto the plane defined by p and n
	//then pmin is projected onto the unit sphere
	float zn=dot(z,n),zp=dot(z,p),np=dot(n,p);
	float alpha=zp-zn*np, beta=zn-zp*np;
	float4 pmin=normalize(alpha*p+min(0.,beta)*n);
	//ca and sa are the cosine and sine of the angle between z and pmin. This is the spherical distance.
	float ca=dot(z,pmin), sa=0.5*length(pmin-z)*length(pmin+z);//sqrt(1.-ca*ca);//
	float factor = 1.0;// DD(ca,sa,r)/DD(ca+0.01,sa,r);
	return (DD(ca,sa,r)-sRadius*factor)*min(1.0/factor,1.0);
	
}

float dist2Segments(float4 p, float4 z, float r, float4 nc, float4 nd, float srad){
	float da=dist2Segment(p, z, float4(1.,0.,0.,0.), r, srad);
	float db=dist2Segment(p, z, float4(0.,1.,0.,0.), r, srad);
	float dc=dist2Segment(p, z, nc, r, srad);
	float dd=dist2Segment(p, z, nd, r, srad);
	
	return min(min(da,db),min(dc,dd));
}

float DE(float4 p, float3 pos, float3x3 rot, float4 nc, float4 nd, float vrad, float srad, inout float m) {
	
	float r=length(pos);
	float4 z4=float4(2.*pos,1.-r*r)*1./(1.+r*r);//Inverse stereographic projection of pos: z4 lies onto the unit 3-sphere centered at 0.
	z4.xyw=mul(z4.xyw, rot);
	z4=fold(z4, nc, nd);//fold it
	float d=10000.;
	
	d = min(d, dist2Vertex(p, z4,r, vrad));
	
	float seg = dist2Segments(p, z4, r, nc, nd, srad);
    m = d <= seg;
    
    d = min(seg, d);

	return d ;
}

float distanceFunction(float3 p, inout float m) {
    float rotX = _Rotation.x;   // [0 - 1]
	float rotY = _Rotation.y;   // [0 - 1]
	float rotZ = _Rotation.z;   // [0 - 1]

    float angle = _time * _TimeScale;
	
	// init
	float3x3 rot;
	float4 nc, nd, wp;
	
	float cospin=cos(PI/float(_Degrees)), isinpin=1./sin(PI/float(_Degrees));
	float scospin=sqrt(2./3.-cospin*cospin), issinpin=1./sqrt(3.-4.*cospin*cospin);

	nc=0.5*float4(0,-1,sqrt(3.),0.);
	nd=float4(-cospin,-0.5,-0.5/sqrt(3.),scospin);

	float4 pabc,pbdc,pcda,pdba;
	pabc=float4(0.,0.,0.,1.);
	pbdc=0.5*sqrt(3.)*float4(scospin,0.,0.,cospin);
	pcda=isinpin*float4(0.,0.5*sqrt(3.)*scospin,0.5*scospin,1./sqrt(3.));
	pdba=issinpin*float4(0.,0.,2.*scospin,1./sqrt(3.));
	
	wp=normalize(_V*pabc+_U*pbdc+_W*pcda+_T*pdba);

	rot = rot3D(normalize(float3(rotX,rotY,rotZ)), PI*(angle/360.0));//in reality we need a 4D rotation

    return DE(wp, p * _Scale, rot, nc, nd, _VRad, _SRad, m);
}

DistanceFunctionSurfaceData getDistanceFunctionSurfaceData(float3 p, float m) {
    DistanceFunctionSurfaceData surface = initDistanceFunctionSurfaceData();
    
    float3 positionWS = GetAbsolutePositionWS(p);
    surface.Position = p;
    surface.Normal   = normal(p, 0.00001);
    surface.Occlusion = ao(p, surface.Normal, 1.0) * max(smoothstep(-40.0, -20.0, positionWS.y), 0.3);
    // Normally BentNormal is the average direction of unoccluded ambient light, but AO * Normal is used instead because of high calculation load.
    surface.BentNormal = surface.Normal * surface.Occlusion;
    surface.Albedo = lerp(_BaseColor.xyz, float3(.5,.25,.78), m);
    surface.Smoothness = _Smoothness;
    surface.Metallic = lerp(.95, _Metallic, m);
    surface.Emissive = 0;
    return surface;
}
/** Original decorative material studies, not data visualizations. No clock/seed loop. */
export const artworkWgsl = /* wgsl */ `
struct ArtworkParams {
  charcoal: vec4f,
  blue: vec4f,
  orange: vec4f,
  platinum: vec4f,
  resolution: vec2f,
  pointer: vec2f,
  variant: f32,
  hover: f32,
};
@group(0) @binding(0) var<uniform> params: ArtworkParams;

fn turn(p: vec2f, angle: f32) -> vec2f {
  let c = cos(angle); let s = sin(angle);
  return vec2f(c*p.x-s*p.y, s*p.x+c*p.y);
}
fn band(distance: f32, width: f32) -> f32 {
  return exp(-distance*distance / max(width*width, 0.00001));
}
fn hash2(p: vec2f) -> vec2f {
  return fract(sin(vec2f(dot(p, vec2f(127.1,311.7)), dot(p,vec2f(269.5,183.3))))*43758.5453);
}

@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let aspect = params.resolution.x / max(params.resolution.y, 1.0);
  let p = (uv-0.5)*vec2f(aspect,1.0) + params.pointer*0.018;
  let v = i32(params.variant);
  var ground = params.charcoal.rgb;
  var lead = params.blue.rgb;
  var accent = params.platinum.rgb;
  var body = 0.0;
  var edge = 0.0;
  var warmth = 0.0;

  if (v == 0) {
    // Folded satin: broad overlapping planes with a luminous rolled seam.
    let q = turn(p, -0.57);
    let fold = q.y + 0.15*sin(q.x*5.0) - 0.06;
    body = 0.19 + 0.63*band(fold,0.24)*(0.6+0.4*smoothstep(-0.4,0.35,q.x));
    edge = 0.64*band(fold+0.065,0.025) + 0.22*band(q.y-0.3,0.13);
    warmth = 0.1*band(q.y+0.35,0.12);
  } else if (v == 1) {
    // Interference: two off-axis wave sources, cropped into a soft lens.
    let a = length((p-vec2f(-0.31,0.1))*vec2f(0.83,1.1));
    let b = length(p-vec2f(0.3,-0.16));
    let waves = 0.5+0.5*cos((a-b)*41.0);
    let lens = band(length(p*vec2f(0.85,1.0)),0.59);
    body = 0.12+0.58*lens*(0.22+0.78*waves);
    edge = 0.43*pow(waves,8.0)*lens;
    warmth = 0.14*band(b-0.33,0.12);
  } else if (v == 2) {
    // Prismatic terraces: offset blue planes, distinct from Patchbay's weave.
    let q = turn(p,-0.55);
    let terrace = floor((q.x+0.9)*5.0);
    let height = q.y + terrace*0.065;
    let planes = 0.5+0.5*cos(height*15.0);
    body = 0.13+0.60*planes*band(q.x,0.65);
    edge = 0.45*band(fract(height*2.4)-0.5,0.07);
  } else if (v == 3) {
    // Flow: a warm, continuous S-shaped ribbon, with darker pooled folds.
    lead = params.orange.rgb;
    let q = turn(p,-0.18);
    let ribbon = q.y - 0.23*sin(q.x*5.5);
    body = 0.12+0.84*band(ribbon,0.22);
    edge = 0.47*band(ribbon+0.075,0.028)*(0.6+0.4*cos(q.x*3.0));
    warmth = 0.18*band(ribbon-0.22,0.12);
  } else if (v == 4) {
    // Orbit: tilted, nested elliptical bands around an offset dark aperture.
    lead = params.orange.rgb;
    let q = turn(p-vec2f(0.1,-0.04),-0.62)*vec2f(0.77,1.42);
    let radius = length(q);
    body = 0.08+0.77*band(radius-0.35,0.105)+0.28*band(radius-0.6,0.045);
    edge = 0.56*band(radius-0.29,0.018)*smoothstep(-0.4,0.25,q.y);
    warmth = 0.17*band(radius-0.48,0.07);
  } else if (v == 5) {
    // Facets: angular fan, not a recolored ribbon or circular study.
    lead = params.orange.rgb;
    let q = p-vec2f(-0.25,0.24);
    let angle = atan2(q.y,q.x);
    let facet = fract((angle+3.14159)*1.91);
    let radial = band(length(q)-0.42,0.5);
    body = 0.13+0.72*radial*(0.24+0.76*facet);
    edge = 0.39*band(facet-0.94,0.07)*radial;
    warmth = 0.1*band(q.y+q.x*0.3,0.15);
  } else if (v == 6) {
    // Woven platinum: interlaced broad metallic strands, with alternating lift.
    lead = params.platinum.rgb; accent = params.blue.rgb;
    let q = turn(p,0.35);
    let x = q.x+0.025*sin(q.y*17.0);
    let y = q.y+0.025*sin(q.x*17.0);
    let warp = pow(0.5+0.5*cos(x*34.0),3.0);
    let weft = pow(0.5+0.5*cos(y*34.0),3.0);
    let over = 0.5+0.5*sin(x*17.0)*sin(y*17.0);
    body = 0.2+0.68*mix(warp,weft,over);
    edge = 0.19*max(warp,weft)*band(p.x+p.y,0.48);
    warmth = 0.065*min(warp,weft);
  } else if (v == 7) {
    // Cellular alloy: irregular softly inflated cells and recessed boundaries.
    lead = params.platinum.rgb; accent = params.blue.rgb;
    let q = (p+0.5)*5.2;
    let cell = floor(q);
    var nearest = 8.0;
    var second = 8.0;
    for (var y = -1; y <= 1; y++) {
      for (var x = -1; x <= 1; x++) {
        let neighbor = vec2f(f32(x),f32(y));
        let site = neighbor+0.2+0.6*hash2(cell+neighbor)-fract(q);
        let d = dot(site,site);
        if (d < nearest) { second = nearest; nearest = d; }
        else { second = min(second,d); }
      }
    }
    let rim = smoothstep(0.015,0.27,second-nearest);
    body = 0.15+0.69*rim*(0.55+0.45*band(nearest,0.42));
    edge = 0.21*band(second-nearest-0.055,0.03);
    warmth = 0.07*band(p.x-p.y-0.3,0.22);
  } else if (v == 8) {
    // Signal material: layered, bowed parallel striations; no plotted data.
    lead = params.platinum.rgb; accent = params.blue.rgb;
    let q = turn(p,-0.32);
    let curve = q.y+0.17*sin(q.x*4.0)+0.045*sin(q.x*11.0);
    let stripe = 0.5+0.5*cos(curve*62.0);
    let envelope = band(curve,0.4);
    body = 0.11+0.7*pow(stripe,2.0)*envelope;
    edge = 0.23*pow(stripe,12.0)*band(q.x-0.12,0.35);
    warmth = 0.11*band(curve+0.24,0.11);
  } else {
    // Revenue panel: a charcoal field, with light confined to its right edge.
    lead = params.orange.rgb;
    let sheen = p.x*0.55+p.y*0.22-0.34;
    let right = smoothstep(0.25,1.0,uv.x);
    body = 0.055*band(sheen,0.27)*right;
    edge = 0.052*band(sheen-0.16,0.1)*right;
  }

  // Keep the cool and neutral families visibly separate at card scale.
  if (v < 3) { accent = params.blue.rgb; warmth = 0.0; }
  if (v >= 6 && v < 9) { accent = params.platinum.rgb; warmth *= 0.25; }

  let sheen = band(p.x*0.75+p.y*0.4-params.pointer.x*0.12,0.24)*params.hover;
  var color = mix(ground,lead,clamp(body,0.0,0.94));
  color = mix(color,accent,clamp(edge+sheen*select(0.07,0.014,v==9),0.0,0.78));
  color = mix(color,params.orange.rgb,clamp(warmth,0.0,0.2));
  // Subpixel grain is position-fixed; it never flickers or changes on a clock.
  let grain = (hash2(uv*params.resolution).x-0.5)*0.009;
  let vignette = 1.0-0.16*smoothstep(0.27,0.78,length(uv-0.5));
  return vec4f(clamp(color*vignette+grain,vec3f(0.0),vec3f(1.0)),1.0);
}
`

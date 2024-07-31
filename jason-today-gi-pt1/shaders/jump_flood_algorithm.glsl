#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
// layout(set=0,binding=1,rgba32f)uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;

layout(push_constant,std430)uniform Params{
    vec2 oneOverSize;
    float uOffset;
    bool skip;
}pc;

const float FLT_MAX = 3.4028235e38;

void main(){
    vec2 fragCoord=gl_GlobalInvocationID.xy;
    ivec2 ifragCoord=ivec2(fragCoord.xy);
    ivec2 input_image_size=imageSize(input_image).xy;
    vec2 vUv=fragCoord.xy/input_image_size;
    vec4 fragColor;

    if(pc.skip){
        fragColor=vec4(vUv,0.,1.);
        imageStore(output_image,ifragCoord,fragColor);
        return;
    }

    vec4 nearestSeed=vec4(-2.);
    float nearestDist=FLT_MAX;
    
    for(float y=-1.;y<=1.;y+=1.){
        for(float x=-1.;x<=1.;x+=1.){

            vec2 sampleXY = fragCoord + vec2(x, y) * pc.uOffset;

            // Check if the sample is within bounds
            if (sampleXY.x < 0.0 || sampleXY.x >= input_image_size.x || 
                sampleXY.y < 0.0 || sampleXY.y >= input_image_size.y) {
                continue;
            }

            vec4 sampleValue=imageLoad(input_image, ivec2(sampleXY));
            vec2 sampleSeed=sampleValue.xy;

            if(sampleSeed.x!=0.||sampleSeed.y!=0.){
                vec2 diff = sampleSeed - fragCoord;
                float dist=dot(diff,diff);
                if(dist<nearestDist){
                    nearestDist=dist;
                    nearestSeed=sampleValue;
                }
            }
        }
    }
    fragColor=nearestSeed;

    imageStore(output_image,ifragCoord,fragColor);

}


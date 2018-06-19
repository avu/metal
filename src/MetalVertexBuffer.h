//
// Created by Alexey Ushakov on 14/06/2018.
//

#ifndef METAL_METALVERTEXBUFFER_H
#define METAL_METALVERTEXBUFFER_H


#import "VertexBuffer.h"

@protocol MTLBuffer;

class MetalVertexBuffer : public VertexBuffer {
    id <MTLBuffer> b;

};


#endif //METAL_METALVERTEXBUFFER_H

//
// Created by Alexey Ushakov on 03/05/2018.
//

#ifndef METAL_VERTEXBUFFER_H
#define METAL_VERTEXBUFFER_H

struct Vertex {
    float position[3];
    unsigned char color[4];
};

class VertexBuffer {
    int capacity;
    int size;
    Vertex* vbuf;

public:

    VertexBuffer(int c = 1024) : capacity(c), size(0) {
        vbuf = new Vertex[c];
    }

    int getSize() const {
        return size;
    }

    Vertex* getBuffer() {
        return vbuf;
    }

    Vertex* allocate(int n) {
        if (size + n > capacity)
            return 0;
        int r = size;
        size+=n;
        return vbuf + r;
    }

    virtual ~VertexBuffer() {
        delete [] vbuf;
    }
};


#endif //METAL_VERTEXBUFFER_H

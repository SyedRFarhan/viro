//
//  VROARMeshAnchor.h
//  ViroRenderer
//
//  Copyright (c) 2024-present, Viro Media, Inc.
//  All rights reserved.
//
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree.

#ifndef VROARMeshAnchor_h
#define VROARMeshAnchor_h

#include "VROARAnchor.h"
#include "VROVector3f.h"
#include <vector>

/*
 ARMeshClassification values from ARKit (iOS 13.4+).
 Maps to ARMeshClassification enum values:
   0 = none, 1 = wall, 2 = floor, 3 = ceiling,
   4 = table, 5 = seat, 6 = window, 7 = door
 */
enum class VROARMeshClassification : int {
    None    = 0,
    Wall    = 1,
    Floor   = 2,
    Ceiling = 3,
    Table   = 4,
    Seat    = 5,
    Window  = 6,
    Door    = 7
};

/*
 Anchor representing a chunk of scene reconstruction mesh from ARKit's
 ARMeshAnchor (iOS 13.4+, LiDAR devices). Each anchor covers a spatial
 region and contains a triangle mesh with per-face classification.
 */
class VROARMeshAnchor : public VROARAnchor {

public:

    VROARMeshAnchor() {}
    virtual ~VROARMeshAnchor() {}

    /*
     Vertices in anchor-local coordinate space.
     */
    const std::vector<VROVector3f> &getVertices() const {
        return _vertices;
    }
    void setVertices(std::vector<VROVector3f> vertices) {
        _vertices = std::move(vertices);
    }

    /*
     Triangle face indices (3 ints per triangle).
     */
    const std::vector<int> &getFaceIndices() const {
        return _faceIndices;
    }
    void setFaceIndices(std::vector<int> indices) {
        _faceIndices = std::move(indices);
    }

    /*
     Per-vertex normals.
     */
    const std::vector<VROVector3f> &getNormals() const {
        return _normals;
    }
    void setNormals(std::vector<VROVector3f> normals) {
        _normals = std::move(normals);
    }

    /*
     Per-face classification (one VROARMeshClassification per triangle).
     Index i corresponds to the triangle formed by faceIndices[i*3..i*3+2].
     */
    const std::vector<int> &getClassifications() const {
        return _classifications;
    }
    void setClassifications(std::vector<int> classifications) {
        _classifications = std::move(classifications);
    }

private:

    std::vector<VROVector3f> _vertices;
    std::vector<int> _faceIndices;
    std::vector<VROVector3f> _normals;
    std::vector<int> _classifications;
};

#endif /* VROARMeshAnchor_h */

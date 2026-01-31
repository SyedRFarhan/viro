//
//  VRTARUtils.m
//  ViroReact
//
//  Copyright © 2017 Viro Media. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "VRTARUtils.h"

@implementation VRTARUtils

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(isARSupported:(RCTResponseSenderBlock)callback)
{
  bool result = [VROViewAR isARSupported];
  NSDictionary *props = @{@"isARSupported" : @(result)};
  callback(@[[NSNull null], props]);
}

// Helper function to convert plane classification enum to string
+ (NSString *)stringFromPlaneClassification:(VROARPlaneClassification)classification {
    switch (classification) {
        case VROARPlaneClassification::Wall:
            return @"Wall";
        case VROARPlaneClassification::Floor:
            return @"Floor";
        case VROARPlaneClassification::Ceiling:
            return @"Ceiling";
        case VROARPlaneClassification::Table:
            return @"Table";
        case VROARPlaneClassification::Seat:
            return @"Seat";
        case VROARPlaneClassification::Door:
            return @"Door";
        case VROARPlaneClassification::Window:
            return @"Window";
        case VROARPlaneClassification::Unknown:
            return @"Unknown";
        case VROARPlaneClassification::None:
        default:
            return @"None";
    }
}

+ (NSDictionary *)createDictionaryFromAnchor:(std::shared_ptr<VROARAnchor>) anchor {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

    [dict setObject:[NSString stringWithUTF8String:anchor->getId().c_str()] forKey:@"anchorId"];

    VROMatrix4f transform =  anchor->getTransform();
    VROVector3f position = transform.extractTranslation();
    VROVector3f scale = transform.extractScale();
    VROVector3f rotation = transform.extractRotation(scale).toEuler();

    [dict setObject:@[@(position.x), @(position.y), @(position.z)] forKey:@"position"];
    [dict setObject:@[@(scale.x), @(scale.y), @(scale.z)] forKey:@"scale"];
    [dict setObject:@[@(toDegrees(rotation.x)), @(toDegrees(rotation.y)), @(toDegrees(rotation.z))] forKey:@"rotation"];

    // default type is "anchor", override below.
    [dict setObject:@"anchor" forKey:@"type"];

    std::shared_ptr<VROARPlaneAnchor> planeAnchor = std::dynamic_pointer_cast<VROARPlaneAnchor>(anchor);
    if (planeAnchor) {
        [dict setObject:@"plane" forKey:@"type"];
        [dict setObject:@[@(planeAnchor->getCenter().x), @(planeAnchor->getCenter().y), @(planeAnchor->getCenter().z)] forKey:@"center"];
        [dict setObject:@(planeAnchor->getExtent().x) forKey:@"width"];
        [dict setObject:@(planeAnchor->getExtent().z) forKey:@"height"];
        
        // Set polygon vertices points
        std::vector<VROVector3f> points = planeAnchor->getBoundaryVertices();
        NSMutableArray *pointsArray = [[NSMutableArray alloc] initWithCapacity:points.size()];
        for (VROVector3f point : points) {
            [pointsArray addObject:@[@(point.x), @(point.y), @(point.z)]];
        }
        [dict setObject:pointsArray forKey:@"vertices"];

        switch (planeAnchor->getAlignment()) {
            case VROARPlaneAlignment::Vertical:
                [dict setObject:@"Vertical" forKey:@"alignment"];
                break;
            case VROARPlaneAlignment::Horizontal:
            default:
                [dict setObject:@"Horizontal" forKey:@"alignment"];
                break;
        }

        // Add plane classification (iOS 12+, basic inference on Android)
        VROARPlaneClassification classification = planeAnchor->getClassification();
        NSString *classificationString = [VRTARUtils stringFromPlaneClassification:classification];
        [dict setObject:classificationString forKey:@"classification"];
    }

    // Mesh anchor (ARMeshAnchor from LiDAR scene reconstruction)
    std::shared_ptr<VROARMeshAnchor> meshAnchor = std::dynamic_pointer_cast<VROARMeshAnchor>(anchor);
    if (meshAnchor) {
        [dict setObject:@"mesh" forKey:@"type"];

        const std::vector<VROVector3f> &vertices = meshAnchor->getVertices();
        const std::vector<int> &faceIndices = meshAnchor->getFaceIndices();
        const std::vector<VROVector3f> &normals = meshAnchor->getNormals();
        const std::vector<int> &classifications = meshAnchor->getClassifications();

        [dict setObject:@((int)vertices.size()) forKey:@"vertexCount"];
        [dict setObject:@((int)(faceIndices.size() / 3)) forKey:@"faceCount"];

        // Encode vertices as base64 (float32 x 3 per vertex)
        {
            std::vector<float> flat;
            flat.reserve(vertices.size() * 3);
            for (const auto &v : vertices) {
                flat.push_back(v.x);
                flat.push_back(v.y);
                flat.push_back(v.z);
            }
            NSData *data = [NSData dataWithBytes:flat.data()
                                          length:flat.size() * sizeof(float)];
            [dict setObject:[data base64EncodedStringWithOptions:0] forKey:@"verticesBase64"];
        }

        // Encode face indices as base64 (int32 x 3 per face)
        {
            NSData *data = [NSData dataWithBytes:faceIndices.data()
                                          length:faceIndices.size() * sizeof(int)];
            [dict setObject:[data base64EncodedStringWithOptions:0] forKey:@"indicesBase64"];
        }

        // Encode normals as base64 (float32 x 3 per vertex)
        {
            std::vector<float> flat;
            flat.reserve(normals.size() * 3);
            for (const auto &n : normals) {
                flat.push_back(n.x);
                flat.push_back(n.y);
                flat.push_back(n.z);
            }
            NSData *data = [NSData dataWithBytes:flat.data()
                                          length:flat.size() * sizeof(float)];
            [dict setObject:[data base64EncodedStringWithOptions:0] forKey:@"normalsBase64"];
        }

        // Encode classifications as base64 (int32 per face)
        {
            NSData *data = [NSData dataWithBytes:classifications.data()
                                          length:classifications.size() * sizeof(int)];
            [dict setObject:[data base64EncodedStringWithOptions:0] forKey:@"classificationsBase64"];
        }
    }

    return dict;
}

+ (NSDictionary *)createDictionaryFromARPointCloud:(std::shared_ptr<VROARPointCloud>) pointCloud {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

    std::vector<VROVector4f> points = pointCloud->getPoints();
    NSMutableArray *pointsArray = [[NSMutableArray alloc] initWithCapacity:points.size()];
    
    // note: the 4th value of the VROVector4f is a "confidence" value only meaningful in Android.
    for (VROVector4f point : points) {
        [pointsArray addObject:@[@(point.x), @(point.y), @(point.z), @(point.w)]];
    }

    std::vector<uint64_t> identifiers = pointCloud->getIdentifiers();
    NSMutableArray *identifiersArray = [[NSMutableArray alloc] initWithCapacity:identifiers.size()];

    for (uint64_t identifier : identifiers) {
        [identifiersArray addObject:[NSNumber numberWithUnsignedLongLong:identifier]];
    }

    [dict setObject:pointsArray forKey:@"points"];
    [dict setObject:identifiersArray forKey:@"identifiers"];

    return dict;
}

@end

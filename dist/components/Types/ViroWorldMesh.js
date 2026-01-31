"use strict";
/**
 * Copyright (c) 2024-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ViroMeshClassification = void 0;
/**
 * ARMeshClassification values from ARKit (iOS 13.4+).
 * These map to per-face classifications provided by LiDAR scene reconstruction.
 */
var ViroMeshClassification;
(function (ViroMeshClassification) {
    ViroMeshClassification[ViroMeshClassification["None"] = 0] = "None";
    ViroMeshClassification[ViroMeshClassification["Wall"] = 1] = "Wall";
    ViroMeshClassification[ViroMeshClassification["Floor"] = 2] = "Floor";
    ViroMeshClassification[ViroMeshClassification["Ceiling"] = 3] = "Ceiling";
    ViroMeshClassification[ViroMeshClassification["Table"] = 4] = "Table";
    ViroMeshClassification[ViroMeshClassification["Seat"] = 5] = "Seat";
    ViroMeshClassification[ViroMeshClassification["Window"] = 6] = "Window";
    ViroMeshClassification[ViroMeshClassification["Door"] = 7] = "Door";
})(ViroMeshClassification || (exports.ViroMeshClassification = ViroMeshClassification = {}));

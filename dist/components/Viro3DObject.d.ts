import * as React from "react";
import { ImageSourcePropType, NativeSyntheticEvent } from "react-native";
import { ViroErrorEvent, ViroLoadEndEvent, ViroLoadStartEvent } from "./Types/ViroEvents";
import { ViroBase } from "./ViroBase";
type Props = {
    type: "OBJ" | "VRX" | "GLTF" | "GLB";
    /**
     * The model file, which is required
     */
    source: ImageSourcePropType;
    /**
     * Additional resource files for various model formats
     */
    resources?: ImageSourcePropType[];
    /**
     * Sets morph target weights for GLB/GLTF models that contain morph targets (blend shapes).
     * Each entry pairs a target name (as exported from the model) with a blend weight in [0, 1].
     *
     * Example:
     *   morphTargets={[{ target: "Smile", weight: 0.8 }, { target: "Blink", weight: 1.0 }]}
     *
     * Use getMorphTargets() to discover the available target names at runtime.
     */
    morphTargets?: Array<{
        target?: string;
        weight?: number;
    }>;
    onLoadStart?: (event: NativeSyntheticEvent<ViroLoadStartEvent>) => void;
    onLoadEnd?: (event: NativeSyntheticEvent<ViroLoadEndEvent>) => void;
    onError?: (event: NativeSyntheticEvent<ViroErrorEvent>) => void;
};
/**
 * Viro3DObject is a component that is used to render 3D models in the scene.
 */
export declare class Viro3DObject extends ViroBase<Props> {
    render(): React.JSX.Element;
    _onLoadStart: (event: NativeSyntheticEvent<ViroLoadStartEvent>) => void;
    _onLoadEnd: (event: NativeSyntheticEvent<ViroLoadEndEvent>) => void;
    getBoundingBoxAsync: () => Promise<any>;
    getMorphTargets: () => Promise<any>;
}
export {};

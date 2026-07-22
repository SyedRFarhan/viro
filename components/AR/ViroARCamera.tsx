/**
 * Copyright (c) 2018-present, Viro, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 * @providesModule ViroARCamera
 * @flow
 */
"use strict";

import * as React from "react";
import { ViewProps } from "react-native";
import { ViroCamera } from "../ViroCamera";
import { isQuest } from "../Utilities/ViroPlatform";

export class ViroARCamera extends React.Component<ViewProps> {
  _component: ViroCamera | null = null;

  render() {
    if (isQuest) {
      console.warn("[Viro] ViroARCamera is not supported on Quest and will not render.");
      return null;
    }
    // Uncomment this to check props
    return (
      <ViroCamera
        ref={(component: ViroCamera) => {
          this._component = component;
        }}
        {...this.props}
        active={true}
      />
    );
  }
}

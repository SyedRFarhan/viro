/**
 * Copyright (c) 2024-present, Viro Media, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
/**
 * Status of world map persistence operations.
 * [iOS Only]
 */
export type ViroWorldMapPersistenceStatus = "saving" | "saved" | "loading" | "loaded" | "error" | "notAvailable";
/**
 * Event fired when world map persistence status changes.
 * [iOS Only]
 */
export type ViroWorldMapPersistenceEvent = {
    /**
     * Current status of the persistence operation.
     */
    status: ViroWorldMapPersistenceStatus;
    /**
     * The session ID associated with this event.
     */
    sessionId: string;
    /**
     * Error message if status is "error".
     */
    error?: string;
};
/**
 * Result of a manual saveWorldMap() call.
 * [iOS Only]
 */
export type ViroSaveWorldMapResult = {
    /**
     * Whether the save operation succeeded.
     */
    success: boolean;
    /**
     * Error message if success is false.
     */
    error?: string;
};

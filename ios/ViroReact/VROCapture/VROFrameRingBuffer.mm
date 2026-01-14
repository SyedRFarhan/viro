//
//  VROFrameRingBuffer.mm
//  ViroReact
//
//  Ring buffer implementation for storing AR frame metadata.
//
//  Copyright © 2024 Viro Media. All rights reserved.
//

#import "VROFrameRingBuffer.h"

#pragma mark - VROFrameEntry Implementation

@implementation VROFrameEntry

- (void)dealloc {
    // Release retained CVPixelBuffer if present
    if (_depthBuffer) {
        CVPixelBufferRelease(_depthBuffer);
        _depthBuffer = nil;
    }
}

@end


#pragma mark - VROFrameRingBuffer Implementation

@implementation VROFrameRingBuffer {
    NSMutableDictionary<NSString *, VROFrameEntry *> *_entries;
    NSMutableArray<NSString *> *_order;  // FIFO order for eviction
    NSUInteger _capacity;
    NSInteger _sessionId;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _entries = [NSMutableDictionary dictionaryWithCapacity:capacity];
        _order = [NSMutableArray arrayWithCapacity:capacity];
        _sessionId = 0;
    }
    return self;
}

- (void)addEntry:(VROFrameEntry *)entry {
    @synchronized(self) {
        // Evict oldest entries if at capacity
        while (_order.count >= _capacity) {
            NSString *oldest = _order.firstObject;
            VROFrameEntry *oldEntry = _entries[oldest];

            // Release depth buffer before removing entry
            if (oldEntry.depthBuffer) {
                CVPixelBufferRelease(oldEntry.depthBuffer);
                oldEntry.depthBuffer = nil;
            }

            [_entries removeObjectForKey:oldest];
            [_order removeObjectAtIndex:0];
        }

        // Set session ID on the entry
        entry.sessionId = _sessionId;

        // Add new entry
        _entries[entry.frameId] = entry;
        [_order addObject:entry.frameId];
    }
}

- (VROFrameEntry *)entryForFrameId:(NSString *)frameId {
    @synchronized(self) {
        return _entries[frameId];
    }
}

- (void)incrementSessionId {
    @synchronized(self) {
        _sessionId++;
    }
}

- (NSInteger)currentSessionId {
    @synchronized(self) {
        return _sessionId;
    }
}

@end

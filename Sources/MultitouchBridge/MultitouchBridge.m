#import "MultitouchBridge.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <math.h>

typedef const void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} TTMTPoint;

typedef struct {
    TTMTPoint position;
    TTMTPoint velocity;
} TTMTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    uint32_t state;
    int32_t fingerID;
    int32_t handID;
    TTMTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    TTMTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} TTMTTouch;

typedef CFArrayRef (*TTMTDeviceCreateListFunction)(void);
typedef int32_t (*TTMTDeviceStartFunction)(MTDeviceRef device, int mode);
typedef int32_t (*TTMTDeviceStopFunction)(MTDeviceRef device);
typedef void (*TTMTFrameCallback)(MTDeviceRef device,
                                  TTMTTouch touches[],
                                  size_t numTouches,
                                  double timestamp,
                                  size_t frame);
typedef void (*TTMTFrameCallbackRefcon)(MTDeviceRef device,
                                        TTMTTouch touches[],
                                        size_t numTouches,
                                        double timestamp,
                                        size_t frame,
                                        void *refcon);
typedef void (*TTMTRegisterFrameFunction)(MTDeviceRef device, TTMTFrameCallback callback);
typedef void (*TTMTRegisterFrameRefconFunction)(MTDeviceRef device,
                                                TTMTFrameCallbackRefcon callback,
                                                void *refcon);

static __weak TTMultitouchStream *TTFallbackStream = nil;

@interface TTMultitouchStream () {
    void *_frameworkHandle;
    CFArrayRef _devices;
    TTMTDeviceCreateListFunction _createList;
    TTMTDeviceStartFunction _startDevice;
    TTMTDeviceStopFunction _stopDevice;
    TTMTRegisterFrameFunction _registerFrame;
    TTMTRegisterFrameRefconFunction _registerFrameRefcon;
    BOOL _running;
}
@property (nonatomic, copy, readwrite, nullable) NSString *lastErrorMessage;
@end

@implementation TTMultitouchStream

static void TTDeliverFrame(TTMultitouchStream *stream,
                           TTMTTouch *touches,
                           size_t numTouches,
                           double timestamp) {
    if (stream == nil) {
        return;
    }

    NSInteger state = -1;
    double x = 0.0;
    double y = 0.0;

    if (touches != NULL && numTouches > 0) {
        // Only read the first touch. Recent macOS releases have changed the
        // private struct layout in ways that can make later array entries
        // unreliable, while the first entry and framework-provided count
        // remain sufficient for tap recognition.
        TTMTTouch first = touches[0];
        state = (NSInteger)first.state;
        x = isfinite(first.normalizedVector.position.x) ? first.normalizedVector.position.x : 0.0;
        y = isfinite(first.normalizedVector.position.y) ? first.normalizedVector.position.y : 0.0;
    }

    TTFrameHandler handler = stream.frameHandler;
    if (handler == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        handler((NSInteger)numTouches, state, x, y, timestamp);
    });
}

static void TTFrameCallbackWithRefcon(MTDeviceRef device,
                                      TTMTTouch touches[],
                                      size_t numTouches,
                                      double timestamp,
                                      size_t frame,
                                      void *refcon) {
    (void)device;
    (void)frame;
    TTMultitouchStream *stream = (__bridge TTMultitouchStream *)refcon;
    TTDeliverFrame(stream, touches, numTouches, timestamp);
}

static void TTFrameCallbackFallback(MTDeviceRef device,
                                    TTMTTouch touches[],
                                    size_t numTouches,
                                    double timestamp,
                                    size_t frame) {
    (void)device;
    (void)frame;
    TTDeliverFrame(TTFallbackStream, touches, numTouches, timestamp);
}

- (BOOL)start {
    if (_running) {
        return YES;
    }

    self.lastErrorMessage = nil;
    const char *path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport";
    _frameworkHandle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (_frameworkHandle == NULL) {
        self.lastErrorMessage = @"Could not load MultitouchSupport.framework.";
        return NO;
    }

    _createList = (TTMTDeviceCreateListFunction)dlsym(_frameworkHandle, "MTDeviceCreateList");
    _startDevice = (TTMTDeviceStartFunction)dlsym(_frameworkHandle, "MTDeviceStart");
    _stopDevice = (TTMTDeviceStopFunction)dlsym(_frameworkHandle, "MTDeviceStop");
    _registerFrameRefcon = (TTMTRegisterFrameRefconFunction)dlsym(_frameworkHandle, "MTRegisterContactFrameCallbackWithRefcon");
    _registerFrame = (TTMTRegisterFrameFunction)dlsym(_frameworkHandle, "MTRegisterContactFrameCallback");

    if (_createList == NULL || _startDevice == NULL || _stopDevice == NULL ||
        (_registerFrameRefcon == NULL && _registerFrame == NULL)) {
        self.lastErrorMessage = @"Required MultitouchSupport symbols are unavailable on this macOS version.";
        [self stop];
        return NO;
    }

    _devices = _createList();
    if (_devices == NULL || CFArrayGetCount(_devices) == 0) {
        self.lastErrorMessage = @"No multitouch trackpad was found.";
        [self stop];
        return NO;
    }

    if (_registerFrameRefcon == NULL) {
        TTFallbackStream = self;
    }

    CFIndex count = CFArrayGetCount(_devices);
    for (CFIndex index = 0; index < count; index++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(_devices, index);
        if (_registerFrameRefcon != NULL) {
            _registerFrameRefcon(device, TTFrameCallbackWithRefcon, (__bridge void *)self);
        } else {
            _registerFrame(device, TTFrameCallbackFallback);
        }
        _startDevice(device, 0);
    }

    _running = YES;
    return YES;
}

- (void)stop {
    if (_devices != NULL && _stopDevice != NULL) {
        CFIndex count = CFArrayGetCount(_devices);
        for (CFIndex index = 0; index < count; index++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(_devices, index);
            _stopDevice(device);
        }
        CFRelease(_devices);
        _devices = NULL;
    }

    if (TTFallbackStream == self) {
        TTFallbackStream = nil;
    }

    if (_frameworkHandle != NULL) {
        dlclose(_frameworkHandle);
        _frameworkHandle = NULL;
    }

    _createList = NULL;
    _startDevice = NULL;
    _stopDevice = NULL;
    _registerFrame = NULL;
    _registerFrameRefcon = NULL;
    _running = NO;
}

- (void)dealloc {
    [self stop];
}

@end

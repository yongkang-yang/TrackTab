#import "MultitouchBridge.h"

#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
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
typedef void (*TTMTUnregisterFrameFunction)(MTDeviceRef device, TTMTFrameCallback callback);
typedef void (*TTMTUnregisterFrameRefconFunction)(MTDeviceRef device, TTMTFrameCallbackRefcon callback);

// Reconnecting a trackpad (Bluetooth drop, power cycle, USB replug) creates a
// new MTDevice, so the device list captured at start goes stale. Wait briefly
// after an IOKit add/remove so the new device is fully registered before
// re-reading the list.
static const NSTimeInterval TTDeviceRefreshDelay = 0.5;

static __weak TTMultitouchStream *TTFallbackStream = nil;

@interface TTMultitouchStream () {
    void *_frameworkHandle;
    CFArrayRef _devices;
    TTMTDeviceCreateListFunction _createList;
    TTMTDeviceStartFunction _startDevice;
    TTMTDeviceStopFunction _stopDevice;
    TTMTRegisterFrameFunction _registerFrame;
    TTMTRegisterFrameRefconFunction _registerFrameRefcon;
    TTMTUnregisterFrameFunction _unregisterFrame;
    TTMTUnregisterFrameRefconFunction _unregisterFrameRefcon;
    IONotificationPortRef _notificationPort;
    io_iterator_t _addedIterator;
    io_iterator_t _removedIterator;
    BOOL _running;
}
@property (nonatomic, copy, readwrite, nullable) NSString *lastErrorMessage;
- (void)scheduleDeviceRefresh;
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

static void TTDrainIterator(io_iterator_t iterator) {
    io_object_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOObjectRelease(service);
    }
}

static void TTDevicesChanged(void *refcon, io_iterator_t iterator) {
    TTDrainIterator(iterator);
    TTMultitouchStream *stream = (__bridge TTMultitouchStream *)refcon;
    [stream scheduleDeviceRefresh];
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
    _unregisterFrameRefcon = (TTMTUnregisterFrameRefconFunction)dlsym(_frameworkHandle, "MTUnregisterContactFrameCallbackWithRefcon");
    _unregisterFrame = (TTMTUnregisterFrameFunction)dlsym(_frameworkHandle, "MTUnregisterContactFrameCallback");

    if (_createList == NULL || _startDevice == NULL || _stopDevice == NULL ||
        (_registerFrameRefcon == NULL && _registerFrame == NULL)) {
        self.lastErrorMessage = @"Required MultitouchSupport symbols are unavailable on this macOS version.";
        [self stop];
        return NO;
    }

    if (_registerFrameRefcon == NULL) {
        TTFallbackStream = self;
    }

    _running = YES;
    [self startWatchingDevices];

    // Keep running without a trackpad: the device watcher attaches one as
    // soon as it connects.
    if (![self attachDevices]) {
        self.lastErrorMessage = @"No multitouch trackpad was found. TrackTab will start listening as soon as one connects.";
        return NO;
    }
    return YES;
}

- (void)refreshDevices {
    if (!_running) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshDevices) object:nil];
    [self detachDevices];
    [self attachDevices];
}

- (void)scheduleDeviceRefresh {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshDevices) object:nil];
    [self performSelector:@selector(refreshDevices) withObject:nil afterDelay:TTDeviceRefreshDelay];
}

- (BOOL)attachDevices {
    _devices = _createList();
    if (_devices == NULL || CFArrayGetCount(_devices) == 0) {
        if (_devices != NULL) {
            CFRelease(_devices);
            _devices = NULL;
        }
        return NO;
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
    return YES;
}

- (void)detachDevices {
    if (_devices == NULL) {
        return;
    }

    CFIndex count = CFArrayGetCount(_devices);
    for (CFIndex index = 0; index < count; index++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(_devices, index);
        if (_registerFrameRefcon != NULL && _unregisterFrameRefcon != NULL) {
            _unregisterFrameRefcon(device, TTFrameCallbackWithRefcon);
        } else if (_registerFrameRefcon == NULL && _unregisterFrame != NULL) {
            _unregisterFrame(device, TTFrameCallbackFallback);
        }
        _stopDevice(device);
    }
    CFRelease(_devices);
    _devices = NULL;
}

- (void)startWatchingDevices {
    _notificationPort = IONotificationPortCreate(kIOMainPortDefault);
    if (_notificationPort == NULL) {
        return;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(),
                       IONotificationPortGetRunLoopSource(_notificationPort),
                       kCFRunLoopDefaultMode);

    // Each IOServiceAddMatchingNotification call consumes one reference to
    // its matching dictionary.
    CFMutableDictionaryRef added = IOServiceMatching("AppleMultitouchDevice");
    CFMutableDictionaryRef removed = IOServiceMatching("AppleMultitouchDevice");
    if (added != NULL &&
        IOServiceAddMatchingNotification(_notificationPort, kIOFirstMatchNotification, added,
                                         TTDevicesChanged, (__bridge void *)self,
                                         &_addedIterator) == KERN_SUCCESS) {
        // Arm the notification; devices already present are picked up by
        // the initial attach.
        TTDrainIterator(_addedIterator);
    }
    if (removed != NULL &&
        IOServiceAddMatchingNotification(_notificationPort, kIOTerminatedNotification, removed,
                                         TTDevicesChanged, (__bridge void *)self,
                                         &_removedIterator) == KERN_SUCCESS) {
        TTDrainIterator(_removedIterator);
    }
}

- (void)stopWatchingDevices {
    if (_addedIterator != IO_OBJECT_NULL) {
        IOObjectRelease(_addedIterator);
        _addedIterator = IO_OBJECT_NULL;
    }
    if (_removedIterator != IO_OBJECT_NULL) {
        IOObjectRelease(_removedIterator);
        _removedIterator = IO_OBJECT_NULL;
    }
    if (_notificationPort != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(),
                              IONotificationPortGetRunLoopSource(_notificationPort),
                              kCFRunLoopDefaultMode);
        IONotificationPortDestroy(_notificationPort);
        _notificationPort = NULL;
    }
}

- (void)stop {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshDevices) object:nil];
    [self stopWatchingDevices];

    if (_stopDevice != NULL) {
        [self detachDevices];
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
    _unregisterFrame = NULL;
    _unregisterFrameRefcon = NULL;
    _running = NO;
}

- (void)dealloc {
    [self stop];
}

@end

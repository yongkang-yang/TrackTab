#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TTFrameHandler)(NSInteger touchCount,
                               NSInteger firstTouchState,
                               double x,
                               double y,
                               double timestamp);

@interface TTMultitouchStream : NSObject

@property (nonatomic, copy, nullable) TTFrameHandler frameHandler;
@property (nonatomic, copy, readonly, nullable) NSString *lastErrorMessage;

/// Starts listening and watches for trackpads being connected or removed.
/// Returns NO with `lastErrorMessage` set when no trackpad is present yet;
/// the stream stays running and attaches one as soon as it connects.
- (BOOL)start;
- (void)stop;

/// Re-reads the device list and re-attaches to every trackpad.
- (void)refreshDevices;

@end

NS_ASSUME_NONNULL_END

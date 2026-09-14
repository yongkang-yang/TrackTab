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

- (BOOL)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END

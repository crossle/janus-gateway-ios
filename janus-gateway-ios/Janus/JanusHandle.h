#import <Foundation/Foundation.h>

@class JanusHandle;

typedef void (^OnJoined)(JanusHandle *handle);
typedef void (^OnRemoteJsep)(JanusHandle *handle, NSDictionary *jsep);

@interface JanusHandle : NSObject

@property (readwrite, nonatomic) NSNumber *handleId;
@property (readwrite, nonatomic) NSNumber *feedId;
@property (readwrite, nonatomic) NSString *display;

@property (copy) OnJoined onJoined;
@property (copy) OnRemoteJsep onRemoteJsep;
@property (copy) OnJoined onLeaving;

@end

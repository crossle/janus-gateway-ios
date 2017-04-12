#import <UIKit/UIKit.h>
#import "WebSocketChannel.h"
#import "WebRTC/WebRTC.h"


@protocol WebSocketDelegate <NSObject>
- (void)onPublisherJoined:(NSNumber *)handleId;
- (void)onPublisherRemoteJsep:(NSNumber *)handleId dict:(NSDictionary *)jsep;
- (void)subscriberHandleRemoteJsep: (NSNumber *)handleId dict:(NSDictionary *)jsep;
- (void)onLeaving:(NSNumber *)handleId;
@end


@interface ViewController : UIViewController<RTCPeerConnectionDelegate, WebSocketDelegate, RTCEAGLVideoViewDelegate>

@property(nonatomic, strong) RTCPeerConnectionFactory *factory;

@end



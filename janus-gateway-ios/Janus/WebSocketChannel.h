
#import <Foundation/Foundation.h>
#import "WebRTC/WebRTC.h"
#import "ViewController.h"


@protocol WebSocketDelegate;

typedef NS_ENUM(NSInteger, ARDSignalingChannelState) {
    kARDSignalingChannelStateClosed,
    kARDSignalingChannelStateOpen,
    kARDSignalingChannelStateCreate,
    kARDSignalingChannelStateAttach,
    kARDSignalingChannelStateJoin,
    kARDSignalingChannelStateOffer,
    kARDSignalingChannelStateError
};

@interface WebSocketChannel : NSObject

@property(nonatomic, weak) id<WebSocketDelegate> delegate;

- (instancetype)initWithURL:(NSURL *)url;

- (void)publisherCreateOffer:(NSNumber *)handleId sdp:(RTCSessionDescription *)sdp;

- (void)subscriberCreateAnswer:(NSNumber *)handleId sdp: (RTCSessionDescription *)sdp;

- (void)trickleCandidate:(NSNumber *)handleId candidate: (RTCIceCandidate *)candidate;

- (void)trickleCandidateComplete:(NSNumber *)handleId;

@end

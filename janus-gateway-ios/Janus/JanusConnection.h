
#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

@interface JanusConnection : NSObject

@property (readwrite, nonatomic) NSNumber *handleId;
@property (readwrite, nonatomic) RTCPeerConnection *connection;
@property (readwrite, nonatomic) RTCVideoTrack *videoTrack;
@property (readwrite, nonatomic) RTCEAGLVideoView *videoView;

@end

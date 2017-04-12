#import "WebSocketChannel.h"
#import <Foundation/Foundation.h>

#import "WebRTC/RTCLogging.h"
#import "SRWebSocket.h"
#import "JanusTransaction.h"
#import "JanusHandle.h"


static NSString const *kJanus = @"janus";
static NSString const *kJanusData = @"data";


@interface WebSocketChannel () <SRWebSocketDelegate>
@property(nonatomic, readonly) ARDSignalingChannelState state;

@end

@implementation WebSocketChannel {
    NSURL *_url;
    SRWebSocket *_socket;
    NSNumber *sessionId;
    NSTimer *keepAliveTimer;
    NSMutableDictionary *transDict;
    NSMutableDictionary *handleDict;
    NSMutableDictionary *feedDict;
}

@synthesize state = _state;


- (instancetype)initWithURL:(NSURL *)url {
    if (self = [super init]) {
        _url = url;
        NSArray<NSString *> *protocols = [NSArray arrayWithObject:@"janus-protocol"];
        _socket = [[SRWebSocket alloc] initWithURL:url protocols:(NSArray *)protocols];
        _socket.delegate = self;
        keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(keepAlive) userInfo:nil repeats:YES];
        transDict = [NSMutableDictionary dictionary];
        handleDict = [NSMutableDictionary dictionary];
        feedDict = [NSMutableDictionary dictionary];

        RTCLog(@"Opening WebSocket.");
        [_socket open];
    }
    return self;
}

- (void)dealloc {
  [self disconnect];
}

- (void)setState:(ARDSignalingChannelState)state {
  if (_state == state) {
    return;
  }
  _state = state;
}

- (void)disconnect {
  if (_state == kARDSignalingChannelStateClosed ||
      _state == kARDSignalingChannelStateError) {
    return;
  }
  [_socket close];
    RTCLog(@"C->WSS DELETE close");
}

#pragma mark - SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
  RTCLog(@"WebSocket connection opened.");
  self.state = kARDSignalingChannelStateOpen;
  [self createSession];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
  NSLog(@"====onMessage=%@", message);
  NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
  id jsonObject = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:nil];
  if (![jsonObject isKindOfClass:[NSDictionary class]]) {
    NSLog(@"Unexpected message: %@", jsonObject);
    return;
  }
  NSDictionary *wssMessage = jsonObject;
  NSString *janus = wssMessage[kJanus];
    if ([janus isEqualToString:@"success"]) {
        NSString *transaction = wssMessage[@"transaction"];

        JanusTransaction *jt = transDict[transaction];
        if (jt.success != nil) {
            jt.success(wssMessage);
        }
        [transDict removeObjectForKey:transaction];
    } else if ([janus isEqualToString:@"error"]) {
        NSString *transaction = wssMessage[@"transaction"];
        JanusTransaction *jt = transDict[transaction];
        if (jt.error != nil) {
            jt.error(wssMessage);
        }
        [transDict removeObjectForKey:transaction];
    } else if ([janus isEqualToString:@"ack"]) {
        NSLog(@"Just an ack");
    } else {
        JanusHandle *handle = handleDict[wssMessage[@"sender"]];
        if (handle == nil) {
            NSLog(@"missing handle?");
        } else if ([janus isEqualToString:@"event"]) {
            NSDictionary *plugin = wssMessage[@"plugindata"][@"data"];
            if ([plugin[@"videoroom"] isEqualToString:@"joined"]) {
                handle.onJoined(handle);
            }

            NSArray *arrays = plugin[@"publishers"];
            if (arrays != nil && [arrays count] > 0) {
                for (NSDictionary *publisher in arrays) {
                    NSNumber *feed = publisher[@"id"];
                    NSString *display = publisher[@"display"];
                    [self subscriberCreateHandle:feed display:display];
                }
            }

            if (plugin[@"leaving"] != nil) {
                JanusHandle *jHandle = feedDict[plugin[@"leaving"]];
                if (jHandle) {
                    jHandle.onLeaving(jHandle);
                }
            }

            if (wssMessage[@"jsep"] != nil) {
                handle.onRemoteJsep(handle, wssMessage[@"jsep"]);
            }
        } else if ([janus isEqualToString:@"detached"]) {
            handle.onLeaving(handle);
        }
    }
}


- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
  RTCLogError(@"WebSocket error: %@", error);
  self.state = kARDSignalingChannelStateError;
}

- (void)webSocket:(SRWebSocket *)webSocket
 didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason
         wasClean:(BOOL)wasClean {
    RTCLog(@"WebSocket closed with code: %ld reason:%@ wasClean:%d",
           (long)code, reason, wasClean);
    NSParameterAssert(_state != kARDSignalingChannelStateError);
    self.state = kARDSignalingChannelStateClosed;
    [keepAliveTimer invalidate];
}

#pragma mark - Private

NSString *letters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

- (NSString *)randomStringWithLength: (int)len {
    NSMutableString *randomString = [NSMutableString stringWithCapacity: len];
    for (int i = 0; i< len; i++) {
        uint32_t data = arc4random_uniform((uint32_t)[letters length]);
        [randomString appendFormat: @"%C", [letters characterAtIndex: data]];
    }
    return randomString;
}

- (void)createSession {
    NSString *transaction = [self randomStringWithLength:12];

    JanusTransaction *jt = [[JanusTransaction alloc] init];
    jt.tid = transaction;
    jt.success = ^(NSDictionary *data) {
        sessionId = data[@"data"][@"id"];
        [keepAliveTimer fire];
        [self publisherCreateHandle];
    };
    jt.error = ^(NSDictionary *data) {
    };
    transDict[transaction] = jt;

    NSDictionary *createMessage = @{
        @"janus": @"create",
        @"transaction" : transaction,
                                    };
  [_socket send:[self jsonMessage:createMessage]];
}

- (void)publisherCreateHandle {
    NSString *transaction = [self randomStringWithLength:12];
    JanusTransaction *jt = [[JanusTransaction alloc] init];
    jt.tid = transaction;
    jt.success = ^(NSDictionary *data){
        JanusHandle *handle = [[JanusHandle alloc] init];
        handle.handleId = data[@"data"][@"id"];
        handle.onJoined = ^(JanusHandle *handle) {
            [self.delegate onPublisherJoined: handle.handleId];
        };
        handle.onRemoteJsep = ^(JanusHandle *handle, NSDictionary *jsep) {
            [self.delegate onPublisherRemoteJsep:handle.handleId dict:jsep];
        };

        handleDict[handle.handleId] = handle;
        [self publisherJoinRoom: handle];
    };
    jt.error = ^(NSDictionary *data) {
    };
    transDict[transaction] = jt;

    NSDictionary *attachMessage = @{
                                    @"janus": @"attach",
                                    @"plugin": @"janus.plugin.videoroom",
                                    @"transaction": transaction,
                                    @"session_id": sessionId,
                                    };
    [_socket send:[self jsonMessage:attachMessage]];
}

- (void)createHandle: (NSString *) transValue dict:(NSDictionary *)publisher {
}

- (void)publisherJoinRoom : (JanusHandle *)handle {
    NSString *transaction = [self randomStringWithLength:12];

    NSDictionary *body = @{
                           @"request": @"join",
                           @"room": @1234,
                           @"ptype": @"publisher",
                           @"display": @"ios webrtc",
                           };
    NSDictionary *joinMessage = @{
                                  @"janus": @"message",
                                  @"transaction": transaction,
                                  @"session_id":sessionId,
                                  @"handle_id":handle.handleId,
                                  @"body": body
                                  };
    
    [_socket send:[self jsonMessage:joinMessage]];
}

- (void)publisherCreateOffer:(NSNumber *)handleId sdp: (RTCSessionDescription *)sdp {
    NSString *transaction = [self randomStringWithLength:12];

    NSDictionary *publish = @{
                             @"request": @"configure",
                             @"audio": @YES,
                             @"video": @YES,
                             };

    NSString *type = [RTCSessionDescription stringForType:sdp.type];

    NSDictionary *jsep = @{
                           @"type": type,
                          @"sdp": [sdp sdp],
                           };
    NSDictionary *offerMessage = @{
                                   @"janus": @"message",
                                   @"body": publish,
                                   @"jsep": jsep,
                                   @"transaction": transaction,
                                   @"session_id": sessionId,
                                   @"handle_id": handleId,
                                   };


    [_socket send:[self jsonMessage:offerMessage]];
}

- (void)trickleCandidate:(NSNumber *) handleId candidate: (RTCIceCandidate *)candidate {
    NSDictionary *candidateDict = @{
                                @"candidate": candidate.sdp,
                                @"sdpMid": candidate.sdpMid,
                                @"sdpMLineIndex": [NSNumber numberWithInt: candidate.sdpMLineIndex],
                                };

    NSDictionary *trickleMessage = @{
                                     @"janus": @"trickle",
                                     @"candidate": candidateDict,
                                     @"transaction": [self randomStringWithLength:12],
                                     @"session_id":sessionId,
                                     @"handle_id":handleId,
                                     };

    NSLog(@"===trickle==%@", trickleMessage);
    [_socket send:[self jsonMessage:trickleMessage]];
}

- (void)trickleCandidateComplete:(NSNumber *) handleId {
    NSDictionary *candidateDict = @{
       @"completed": @YES,
       };
    NSDictionary *trickleMessage = @{
                                     @"janus": @"trickle",
                                     @"candidate": candidateDict,
                                     @"transaction": [self randomStringWithLength:12],
                                     @"session_id":sessionId,
                                     @"handle_id":handleId,
                                     };

    [_socket send:[self jsonMessage:trickleMessage]];
}


- (void)subscriberCreateHandle: (NSNumber *)feed display:(NSString *)display {
    NSString *transaction = [self randomStringWithLength:12];
    JanusTransaction *jt = [[JanusTransaction alloc] init];
    jt.tid = transaction;
    jt.success = ^(NSDictionary *data){
        JanusHandle *handle = [[JanusHandle alloc] init];
        handle.handleId = data[@"data"][@"id"];
        handle.feedId = feed;
        handle.display = display;

        handle.onRemoteJsep = ^(JanusHandle *handle, NSDictionary *jsep) {
            [self.delegate subscriberHandleRemoteJsep:handle.handleId dict:jsep];
        };

        handle.onLeaving = ^(JanusHandle *handle) {
            [self subscriberOnLeaving:handle];
        };
        handleDict[handle.handleId] = handle;
        feedDict[handle.feedId] = handle;
        [self subscriberJoinRoom: handle];
    };
    jt.error = ^(NSDictionary *data) {
    };
    transDict[transaction] = jt;

    NSDictionary *attachMessage = @{
                                    @"janus": @"attach",
                                    @"plugin": @"janus.plugin.videoroom",
                                    @"transaction": transaction,
                                    @"session_id": sessionId,
                                    };
    [_socket send:[self jsonMessage:attachMessage]];
}


- (void)subscriberJoinRoom:(JanusHandle*)handle {

    NSString *transaction = [self randomStringWithLength:12];
    transDict[transaction] = @"subscriber";

    NSDictionary *body = @{
                           @"request": @"join",
                           @"room": @1234,
                           @"ptype": @"listener",
                           @"feed": handle.feedId,
                           };

    NSDictionary *message = @{
                                  @"janus": @"message",
                                  @"transaction": transaction,
                                  @"session_id": sessionId,
                                  @"handle_id": handle.handleId,
                                  @"body": body,
                                  };

    [_socket send:[self jsonMessage:message]];
}

- (void)subscriberCreateAnswer:(NSNumber *)handleId sdp: (RTCSessionDescription *)sdp  {
    NSString *transaction = [self randomStringWithLength:12];

    NSDictionary *body = @{
                              @"request": @"start",
                              @"room": @1234,
                              };

    NSString *type = [RTCSessionDescription stringForType:sdp.type];

    NSDictionary *jsep = @{
                           @"type": type,
                           @"sdp": [sdp sdp],
                           };
    NSDictionary *offerMessage = @{
                                   @"janus": @"message",
                                   @"body": body,
                                   @"jsep": jsep,
                                   @"transaction": transaction,
                                   @"session_id": sessionId,
                                   @"handle_id": handleId,
                                   };

    [_socket send:[self jsonMessage:offerMessage]];
}

- (void)subscriberOnLeaving:(JanusHandle *) handle {
    NSString *transaction = [self randomStringWithLength:12];

    JanusTransaction *jt = [[JanusTransaction alloc] init];
    jt.tid = transaction;
    jt.success = ^(NSDictionary *data) {
        [self.delegate onLeaving:handle.handleId];
        [handleDict removeObjectForKey:handle.handleId];
        [feedDict removeObjectForKey:handle.feedId];
    };
    jt.error = ^(NSDictionary *data) {
    };
    transDict[transaction] = jt;

    NSDictionary *message = @{
                                   @"janus": @"detach",
                                   @"transaction": transaction,
                                   @"session_id": sessionId,
                                   @"handle_id": handle.handleId,
                                   };

    [_socket send:[self jsonMessage:message]];
}

- (void)keepAlive {
    NSDictionary *dict = @{
                           @"janus": @"keepalive",
                           @"session_id": sessionId,
                           @"transaction": [self randomStringWithLength:12],
                           };
    [_socket send:[self jsonMessage:dict]];
}

- (NSString *)jsonMessage:(NSDictionary *)dict {
    NSData *message = [NSJSONSerialization dataWithJSONObject:dict
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:nil];
    NSString *messageString = [[NSString alloc] initWithData:message encoding:NSUTF8StringEncoding];
    return messageString;
}


@end



#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Loaded by Apple's /usr/bin/perl so mediaremoted accepts the Now Playing request.
static void *mediaRemote;
static dispatch_queue_t queue;

static BOOL waitForReply(dispatch_semaphore_t semaphore) {
    return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0;
}

static NSDictionary *currentMedia(void) {
    typedef void (*GetPID)(dispatch_queue_t, void (^)(int));
    typedef void (*GetInfo)(dispatch_queue_t, void (^)(NSDictionary *));
    typedef void (*GetPlaying)(dispatch_queue_t, void (^)(bool));
    GetPID getPID = dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationPID");
    GetInfo getInfo = dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingInfo");
    GetPlaying getPlaying = dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    NSString *__unsafe_unretained *titleKey = (NSString *__unsafe_unretained *)dlsym(mediaRemote, "kMRMediaRemoteNowPlayingInfoTitle");
    if (!getPID || !getInfo || !getPlaying || !titleKey) return nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block int pid = 0;
    getPID(queue, ^(int value) { pid = value; dispatch_semaphore_signal(semaphore); });
    if (!waitForReply(semaphore) || pid <= 0) return nil;

    __block NSDictionary *info = nil;
    getInfo(queue, ^(NSDictionary *value) { info = value; dispatch_semaphore_signal(semaphore); });
    if (!waitForReply(semaphore)) return nil;
    NSString *title = info[*titleKey];
    if (![title isKindOfClass:NSString.class]) title = nil;

    __block bool playing = false;
    getPlaying(queue, ^(bool value) { playing = value; dispatch_semaphore_signal(semaphore); });
    if (!waitForReply(semaphore)) return nil;
    return @{ @"id": [NSString stringWithFormat:@"%d|%@", pid, title ?: @""], @"playing": @(playing) };
}

__attribute__((constructor)) static void runMediaCommand(void) {
    @autoreleasepool {
        const char *action = getenv("LOOKAWAY_MEDIA_COMMAND");
        if (!action) return;
        mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!mediaRemote) return;
        queue = dispatch_queue_create("Lookaway.mediaRemote", DISPATCH_QUEUE_SERIAL);

        NSDictionary *result = nil;
        if (strcmp(action, "snapshot") == 0) {
            result = currentMedia();
        } else if (strcmp(action, "pause") == 0 || strcmp(action, "play") == 0) {
            typedef bool (*SendCommand)(int, id);
            typedef void (*GetPID)(dispatch_queue_t, void (^)(int));
            SendCommand send = dlsym(mediaRemote, "MRMediaRemoteSendCommand");
            GetPID getPID = dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationPID");
            if (send) {
                bool sent = send(strcmp(action, "pause") == 0 ? 1 : 0, nil);
                if (sent && getPID) {
                    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                    getPID(queue, ^(int pid) { (void)pid; dispatch_semaphore_signal(semaphore); });
                    waitForReply(semaphore);
                }
                result = @{ @"sent": @(sent) };
            }
        }

        if (!result) result = @{};
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
}

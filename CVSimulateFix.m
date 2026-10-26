#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

extern void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *result);

#pragma mark - 硬件键盘事件（模拟 ⌘V）

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

static IOHIDEventSystemClientRef (*ZKIOHIDEventSystemClientCreate)(CFAllocatorRef);
static void (*ZKIOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef, IOHIDEventRef);
static IOHIDEventRef (*ZKIOHIDEventCreateKeyboardEvent)(CFAllocatorRef, uint64_t, uint32_t,
                                                        uint32_t, Boolean, uint32_t);
static void (*ZKIOHIDEventSetSenderID)(IOHIDEventRef, uint64_t);
static uint64_t (*ZKMachAbsoluteTime)(void);

static BOOL ZKLoadIOKit(void) {
    static BOOL ready = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (iokit) {
            ZKIOHIDEventSystemClientCreate = dlsym(iokit, "IOHIDEventSystemClientCreate");
            ZKIOHIDEventSystemClientDispatchEvent = dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
            ZKIOHIDEventCreateKeyboardEvent = dlsym(iokit, "IOHIDEventCreateKeyboardEvent");
            ZKIOHIDEventSetSenderID = dlsym(iokit, "IOHIDEventSetSenderID");
        }
        void *system = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
        ZKMachAbsoluteTime = dlsym(system ?: RTLD_DEFAULT, "mach_absolute_time");
        ready = (ZKIOHIDEventSystemClientCreate && ZKIOHIDEventSystemClientDispatchEvent &&
                 ZKIOHIDEventCreateKeyboardEvent && ZKIOHIDEventSetSenderID && ZKMachAbsoluteTime);
    });
    return ready;
}

static void ZKDispatchKeyboardUsage(IOHIDEventSystemClientRef client, uint32_t usage, BOOL down) {
    if (!client) return;
    IOHIDEventRef event = ZKIOHIDEventCreateKeyboardEvent(kCFAllocatorDefault,
                                                          ZKMachAbsoluteTime(),
                                                          7, usage, down ? 1 : 0, 0);
    if (!event) return;
    ZKIOHIDEventSetSenderID(event, 0x8000000817319371ULL);
    ZKIOHIDEventSystemClientDispatchEvent(client, event);
    CFRelease(event);
}

static void ZKSendCommandV(void) {
    if (!ZKLoadIOKit()) return;
    static IOHIDEventSystemClientRef client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        client = ZKIOHIDEventSystemClientCreate(kCFAllocatorDefault);
    });
    if (!client) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ZKDispatchKeyboardUsage(client, 0xE3, YES);  // Command
        ZKDispatchKeyboardUsage(client, 0x19, YES);  // V
        usleep(50000);                               // 按住 50ms
        ZKDispatchKeyboardUsage(client, 0x19, NO);
        ZKDispatchKeyboardUsage(client, 0xE3, NO);
    });
}

#pragma mark - 面板隐藏辅助

static void ZKHidePanel(void) {
    Class winClass = objc_getClass("CVPanelWindow");
    if (!winClass) return;
    SEL sel = NSSelectorFromString(@"sharedWindow");
    if (![winClass respondsToSelector:sel]) return;
    id win = ((id (*)(id, SEL))objc_msgSend)(winClass, sel);
    if (!win) return;
    BOOL isHidden = ((BOOL (*)(id, SEL))objc_msgSend)(win, @selector(isHidden));
    if (isHidden) return;
    id controller = ((id (*)(id, SEL))objc_msgSend)(win, NSSelectorFromString(@"controller"));
    if (controller && [controller respondsToSelector:NSSelectorFromString(@"hide")]) {
        ((void (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"hide"));
    }
}

#pragma mark - 核心粘贴拦截

static void (*ZKOrigUpdatePasteboard)(id, SEL, id, id, BOOL);

static void ZKHookUpdatePasteboard(id self, SEL _cmd, id item, id from, BOOL shouldAutoPaste) {
    NSLog(@"[CopyVaultSimulateFix] 🎯 触发条目点击，开始执行模拟粘贴拦截流程...");

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSInteger before = (NSInteger)pasteboard.changeCount;
    ZKOrigUpdatePasteboard(self, _cmd, item, from, NO);

    __block NSInteger checks = 0;
    __block void (^verify)(void) = nil;
    __weak void (^weakVerify)(void) = nil;
    
    verify = ^{
        void (^strongVerify)(void) = weakVerify;
        if ((NSInteger)pasteboard.changeCount != before) {
            NSLog(@"[CopyVaultSimulateFix] ✅ 剪贴板已更新，正在隐藏面板并派发硬件 ⌘V...");
            ZKHidePanel();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ZKSendCommandV();
            });
            return;
        }
        if (++checks < 6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), strongVerify);
            return;
        }
        NSLog(@"[CopyVaultSimulateFix] ⚠️ 剪贴板写入超时，回退到原版经典粘贴方式");
        ZKOrigUpdatePasteboard(self, _cmd, item, from, YES);
    };
    weakVerify = verify;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), verify);
}

#pragma mark - 插件入口（改为全局注入 + 内部 Bundle ID 动态认证）

__attribute__((constructor)) static void CVSimulateFixInit(void) {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *bundleId = [mainBundle bundleIdentifier];
    
    // 打印所有加载该动态库的进程，方便我们看它到底进没进去
    NSLog(@"[CopyVaultSimulateFix] 🚀 动态库被加载进进程: %@", bundleId);

    // 如果不是 CopyVault，直接返回不处理
    if (!bundleId || ![bundleId isEqualToString:@"cn.octoforce.copyvault"]) {
        return;
    }

    NSLog(@"[CopyVaultSimulateFix] 🎉 成功识别到目标 App: cn.octoforce.copyvault，开始挂钩...");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("CopyVaultManager");
        if (!cls) {
            NSLog(@"[CopyVaultSimulateFix] ❌ 未能找到 CopyVaultManager 类");
            return;
        }
        SEL sel = NSSelectorFromString(@"updatePasteboardWithItem:from:shouldAutoPaste:");
        if (class_getInstanceMethod(cls, sel)) {
            MSHookMessageEx(cls, sel, (IMP)ZKHookUpdatePasteboard, (IMP *)&ZKOrigUpdatePasteboard);
            NSLog(@"[CopyVaultSimulateFix] 🎉 CopyVaultManager 粘贴方法 Hook 成功！");
        } else {
            NSLog(@"[CopyVaultSimulateFix] ❌ 未能找到对应的粘贴选择器");
        }
    });
}

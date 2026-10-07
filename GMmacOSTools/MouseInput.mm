#import <Cocoa/Cocoa.h>
#include "MouseInputQueue.hpp"
#include <cstdio>
#include <mutex>

void gm_install_lifecycle_hooks(NSWindow *window);

namespace {
std::mutex mouseMutex;
gm_input::MouseInputQueue mouseQueue;
bool mouseReady = false;
id mouseMonitor = nil;
NSMutableArray *mouseObservers = nil;
NSWindow *mouseWindow = nil;
NSTrackingArea *mouseTracking = nil;
bool previousAcceptsMoved = false;
char mouseSnapshot[256];

void cancelMouseInput() {
    std::lock_guard<std::mutex> lock(mouseMutex);
    mouseQueue.cancel();
}

void stopMouseMonitor() {
    if (mouseMonitor) [NSEvent removeMonitor:mouseMonitor];
    mouseMonitor = nil;
    for (id observer in mouseObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    mouseObservers = nil;
    if (mouseTracking) [mouseWindow.contentView removeTrackingArea:mouseTracking];
    mouseTracking = nil;
    mouseWindow.acceptsMouseMovedEvents = previousAcceptsMoved;
    mouseWindow = nil;
    std::lock_guard<std::mutex> lock(mouseMutex);
    mouseReady = false;
    mouseQueue.cancel();
}

void observeCancellation(NSNotificationName name, id object) {
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:object
        queue:nil usingBlock:^(NSNotification *notification) {
            cancelMouseInput();
        }];
    [mouseObservers addObject:observer];
}
} // namespace

extern "C" double gm_mouse_start() {
    dispatch_async(dispatch_get_main_queue(), ^{
        stopMouseMonitor();
        NSWindow *window = NSApp.mainWindow ?: NSApp.keyWindow;
        if (!window || [window isKindOfClass:NSPanel.class]) {
            window = nil;
            for (NSWindow *candidate in NSApp.windows) {
                if (![candidate isKindOfClass:NSPanel.class] && candidate.contentView) {
                    window = candidate;
                    break;
                }
            }
        }
        if (!window || !window.contentView) return;
        gm_install_lifecycle_hooks(window);
        mouseWindow = window;
        previousAcceptsMoved = window.acceptsMouseMovedEvents;
        window.acceptsMouseMovedEvents = YES;
        mouseTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
            options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                    NSTrackingActiveAlways | NSTrackingInVisibleRect
            owner:window.contentView userInfo:nil];
        [window.contentView addTrackingArea:mouseTracking];

        mouseObservers = [NSMutableArray new];
        observeCancellation(NSApplicationDidResignActiveNotification, NSApp);
        observeCancellation(NSWindowDidResignKeyNotification, window);
        observeCancellation(NSWindowDidResizeNotification, window);
        observeCancellation(NSWindowWillBeginSheetNotification, window);
        observeCancellation(NSMenuDidBeginTrackingNotification, nil);
        [mouseObservers addObject:[NSNotificationCenter.defaultCenter
            addObserverForName:NSWindowWillCloseNotification object:window queue:nil
            usingBlock:^(NSNotification *notification) { stopMouseMonitor(); }]];

        NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp |
            NSEventMaskRightMouseDown | NSEventMaskRightMouseUp |
            NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp |
            NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
            NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDragged |
            NSEventMaskMouseEntered | NSEventMaskMouseExited | NSEventMaskScrollWheel;
        mouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
            // Observe only our renderer window; sheets and native controls retain
            // AppKit's normal input. Background computer-use events are valid too.
            if (event.window != mouseWindow || mouseWindow.attachedSheet ||
                (NSApp.modalWindow && NSApp.modalWindow != mouseWindow)) return event;
            auto kind = gm_input::MouseKind::move;
            switch (event.type) {
                case NSEventTypeLeftMouseDown: case NSEventTypeRightMouseDown:
                case NSEventTypeOtherMouseDown: kind = gm_input::MouseKind::down; break;
                case NSEventTypeLeftMouseUp: case NSEventTypeRightMouseUp:
                case NSEventTypeOtherMouseUp: kind = gm_input::MouseKind::up; break;
                default: break;
            }
            NSView *content = mouseWindow.contentView;
            NSPoint point = [content convertPoint:event.locationInWindow fromView:nil];
            NSRect bounds = content.bounds;
            if (bounds.size.width <= 0 || bounds.size.height <= 0) return event;
            if (kind == gm_input::MouseKind::down && !NSPointInRect(point, bounds)) return event;
            double x = (point.x - bounds.origin.x) / bounds.size.width;
            double y = (point.y - bounds.origin.y) / bounds.size.height;
            if (!content.isFlipped) y = 1.0 - y;
            unsigned button = event.buttonNumber < 3 ? (1u << event.buttonNumber) : 0;
            if (kind != gm_input::MouseKind::move && !button) return event;
            std::lock_guard<std::mutex> lock(mouseMutex);
            mouseQueue.push({kind, button, x, y, NSProcessInfo.processInfo.systemUptime});
            return event; // Do not synthesize, consume, or alter the native event.
        }];
        std::lock_guard<std::mutex> lock(mouseMutex);
        mouseReady = mouseMonitor != nil;
    });
    return 1;
}

extern "C" const char *gm_mouse_poll() {
    std::lock_guard<std::mutex> lock(mouseMutex);
    auto frame = mouseQueue.step(NSProcessInfo.processInfo.systemUptime);
    // Screenshot overlays can swallow Command's release event.
    bool command = (NSEvent.modifierFlags & NSEventModifierFlagCommand) != 0;
    std::snprintf(mouseSnapshot, sizeof(mouseSnapshot),
        "{\"ready\":%d,\"valid\":%d,\"x\":%.17g,\"y\":%.17g,"
        "\"held\":%u,\"pressed\":%u,\"released\":%u,\"cancelled\":%d,\"command\":%d}",
        mouseReady, frame.valid, frame.x, frame.y,
        frame.held, frame.pressed, frame.released, frame.cancelled, command);
    return mouseSnapshot;
}

extern "C" double gm_mouse_clear(double mask) {
    std::lock_guard<std::mutex> lock(mouseMutex);
    mouseQueue.clearButtons(static_cast<unsigned>(mask));
    return 1;
}

extern "C" double gm_mouse_stop() {
    cancelMouseInput();
    dispatch_async(dispatch_get_main_queue(), ^{ stopMouseMonitor(); });
    return 1;
}
